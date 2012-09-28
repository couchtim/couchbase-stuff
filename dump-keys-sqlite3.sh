#! /bin/sh

die () { echo "FATAL ERROR:" "$@" >&2; exit 2; }

sqlite=/opt/couchbase/bin/sqlite3
[ -x "$sqlite" ] || die "Can't find sqlite command-line executable at '$sqlite'"

if [ $# -ne 1 ]; then
    echo "Usage: $0 /path/to/bucket-data/bucket"
    echo "ex: $0 /opt/couchbase/var/lib/couchbase/data/default-data/default"
    exit 1
fi

bucket=$1
[ -r "$bucket" ] || die "Can't read database file '$bucket'"

active=`"$sqlite" "$bucket" 'SELECT vbid FROM vbucket_states WHERE state LIKE "active"' | xargs`

echo "# $active"
for part in 0 1 2 3; do
    # Process each bucket-{0,1,2,3}.mb file in turn, to
    # take more advantage of filesystem buffer
    for vbid in $active; do
        [ `expr "$vbid" \% 4` -eq $part ] || continue
        file="$bucket-$part.mb"
        "$sqlite" "$file" "SELECT hex(k) FROM kv_$vbid"
    done
done
