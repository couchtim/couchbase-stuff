#! /bin/sh

note () { echo "$@" >&2; }
die () { note "FATAL ERROR:" "$@"; exit 2; }

usage () {
    cat <<EOF
Usage: $0 [options] /path/to/bucket-data/bucket

Options:
  -f REGEX   Filter the list of keys on (egrep) REGEX

Examples:

Print all keys in default bucket:
  $0 /opt/couchbase/var/lib/couchbase/data/default-data/default

Print keys starting with 'foo' in 'example' bucket:
  $0 -f '^foo' /opt/couchbase/var/lib/couchbase/data/example-data/example
EOF
}

sqlite=/opt/couchbase/bin/sqlite3
[ -x "$sqlite" ] || die "Can't find sqlite command-line executable at '$sqlite'"

filter=
while getopts df: name
do
    case $name in
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

active=$("$sqlite" "$bucket" 'SELECT vbid FROM vbucket_states WHERE state LIKE "active"')
[ $? -eq 0 ] || die "sqlite3 error reading active vbuckets for $bucket: $?"

activeCount=$(echo "$active" | wc -l)
[ $activeCount -gt 0 ] || die "No active vbuckets for $bucket on this host"
note "Reading keys from $activeCount active vbuckets"

seenVbuckets=0
seenItems=1
matchedItems=0

for part in 0 1 2 3; do
    # Process each bucket-{0,1,2,3}.mb file in turn, to
    # take more advantage of filesystem buffer
    for vbid in $active; do
        [ $(expr "$vbid" \% 4) -eq $part ] || continue
        seenVbuckets=$((seenVbuckets + 1))
        file="$bucket-$part.mb"
        "$sqlite" "$file" "SELECT k FROM kv_$vbid"
    done
done | while read k; do
    seenItems=$((seenItems + 1))
    match=0
    [ -n "$filter" ] && $(echo "$k" | egrep "$filter" > /dev/null) && match=1
    if [ $match -eq 1 ]; then
        matchedItems=$((matchedItems + 1))
        echo "$k"
    fi
    if [ $(expr $seenItems % 1000) -eq 0 ]; then
        printf "matched %d / seen %d\n" "$matchedItems" "$seenItems" >&2
        #sleep 10
    fi
done
