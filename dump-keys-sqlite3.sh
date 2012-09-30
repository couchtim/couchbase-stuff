#! /bin/sh

note () { echo "$@" >&2; }
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

if [ $allkeys -eq 1 -a -n "$filter" -o $allkeys -eq 0 -a -z "$filter" ]; then
    usage "One of -a or -f REGEX must be specified" >&2
    exit 1
fi

shift $(($OPTIND - 1))

if [ $# -ne 1 ]; then
    usage >&2
    exit 1
fi

bucket=$1
[ -r "$bucket" ] || die "Can't read database file '$bucket'"

active=$("$sqlite" "$bucket" 'SELECT vbid FROM vbucket_states WHERE state LIKE "active"')
[ $? -eq 0 ] || die "sqlite3 error reading active vbuckets for $bucket: $?"

activeCount=$(echo "$active" | wc -l)
[ $activeCount -gt 0 ] || die "No active vbuckets for $bucket on this host"
note "Reading keys from $activeCount active vbuckets"

seenItems=0
matchedItems=0

(
    for part in 0 1 2 3; do
        # Process each bucket-{0,1,2,3}.mb file in parallel
        (
            for vbid in $active; do
                [ $(expr "$vbid" \% 4) -eq $part ] || continue
                file="$bucket-$part.mb"
                "$sqlite" "$file" "SELECT k FROM kv_$vbid"
            done
        ) &
    done
    wait
) | (
    while read k; do
        seenItems=$((seenItems + 1))
        match=0
        if [ -n "$filter" ]; then
            $(echo "$k" | egrep "$filter" > /dev/null) && match=1
        else
            match=1
        fi

        if [ $match -eq 1 ]; then
            matchedItems=$((matchedItems + 1))
            echo "$k"
        fi
        if [ $(expr $seenItems % 1000) -eq 0 ]; then
            printf "matched %d / seen %d\n" "$matchedItems" "$seenItems" >&2
            #sleep 10
        fi
    done
    printf "matched %d / seen %d\n" "$matchedItems" "$seenItems" >&2
    note "Done (matched $matchedItems keys)"
)
