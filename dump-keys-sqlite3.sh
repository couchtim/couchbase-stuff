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
while getopts af: name
do
    case $name in
        a)  allkeys=1 ;;
        f)  filter=$OPTARG ;;
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

if [ -n "$filter" ]; then
    filter_func=egrep_filter
else
    filter_func=cat
fi

egrep_filter () { egrep "$filter"; }


active=$("$sqlite" "$bucket" 'SELECT vbid FROM vbucket_states WHERE state LIKE "active"')
[ $? -eq 0 ] || die "sqlite3 error reading active vbuckets for $bucket: $?"

activeCount=$(echo "$active" | wc -l)
[ $activeCount -gt 0 ] || die "No active vbuckets for $bucket on this host"
note "Reading keys from $activeCount active vbuckets"

(
    for part in 0 1 2 3; do
        # Process each bucket-{0,1,2,3}.mb file in parallel
        (
            for vbid in $active; do
                [ $(expr "$vbid" \% 4) -eq $part ] || continue
                # Print *something* for progress indication
                notef "."
                file="$bucket-$part.mb"
                "$sqlite" "$file" "SELECT k FROM kv_$vbid"
            done
        ) &
    done
    wait
) | $filter_func

notef "\nDone\n"
