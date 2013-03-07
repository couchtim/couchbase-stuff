#! /bin/sh

# This script is in the public domain, and comes with NO WARRANTY OF ANY KIND

# Reads keys for all active vbuckets on a Couchbase node, directly
# from the underlying sqlite data files. Optionally filters the key
# names via regex (egrep).

# This script has been tested with bash, dash and ksh shells.

note () { echo "$@" >&2; }
notef () { printf "$@" >&2; }
die () { note "FATAL ERROR:" "$@"; exit 2; }

usage () {
    [ $# -gt 0 ] && echo "$@" >&2
    cat <<EOF
Usage: $0 [options] /path/to/bucket-data/bucket

Options:
  -a         Dump all keys (no filter)
  -f REGEX   Filter the list of keys on (egrep) REGEX
  -t         Print TTL (expiry time) also

Examples:

Print all keys in default bucket:
  $0 -a /opt/couchbase/var/lib/couchbase/data/default-data/default

Print keys starting with 'foo' in 'example' bucket:
  $0 -f '^foo' /opt/couchbase/var/lib/couchbase/data/example-data/example
EOF
}

sqlite=/opt/couchbase/bin/sqlite3
[ -x "$sqlite" ] || die "Can't find sqlite command-line executable at '$sqlite'"

allkeys=0
filter=
ttl=0
while getopts af:t name
do
    case $name in
        a)  allkeys=1 ;;
        f)  filter=$OPTARG ;;
        t)  ttl=1 ;;
        ?)  usage; exit 1 ;;
    esac
done

shift $(($OPTIND - 1))

if [ $# -ne 1 ]; then
    usage >&2
    exit 1
fi

bucket=$1
[ -r "$bucket" ] || die "Can't read database file '$bucket'"

if [ $allkeys -eq 1 -a -n "$filter" -o $allkeys -eq 0 -a -z "$filter" ]; then
    usage "One of -a or -f REGEX must be specified" >&2
    exit 1
fi

egrep_filter () {
    egrep "$filter";
    # Grep returns 1 if no match; treat that as success
    if [ $? -le 1 ]; then return 0; else return $?; fi
}

if [ -n "$filter" ]; then
    filter_func=egrep_filter
else
    filter_func=cat
fi

if [ $ttl -eq 1 ]; then
    # Interpolated into SQL SELECT list
    ttl_field='exptime, '
    # If filter anchors at beginning, ignore the TTL
    filter=`echo "$filter" | sed 's,^\^,^\\d+\\|,'`
else
    ttl_field=
fi

active=$("$sqlite" "$bucket" 'SELECT vbid FROM vbucket_states WHERE state LIKE "active"')
[ $? -eq 0 ] || die "sqlite3 error reading active vbuckets for $bucket: $?"

active_count=$(echo "$active" | wc -l)
[ $active_count -gt 0 ] || die "No active vbuckets for $bucket on this host"

note "Reading keys from $active_count active vbuckets"

for part in 0 1 2 3; do
    for vbid in $active; do
        [ $(expr "$vbid" \% 4) -eq $part ] || continue
        file="$bucket-$part.mb"

        # This is it! Sqlite CLI output goes to stdout
        "$sqlite" "$file" "SELECT ${ttl_field}k FROM kv_$vbid"
        e=$?

        if [ $e -eq 0 ]; then
            # Print *something* for progress indication
            notef "."
        elif [ $e -eq 141 ]; then
            # 141 = 128 + 13 (SIGPIPE); i.e., the filter func quit or was killed
            break
        else
            die "sqlite3 error $e reading table 'kv_$vbid' from '$file'"
        fi
    done
done \
    | $filter_func

if [ $? -ne 0 ]; then
    die "error with filter (bad regex?)"
fi

notef "\nDone\n"
