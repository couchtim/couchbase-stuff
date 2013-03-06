#! /usr/bin/env python2.6

import optparse
import os
import re
import sys

try:
    import sqlite3
except:
    print >> sys.stderr, """This tool requires the sqlite3 python module, which comes with Python 2.6+.
Please run it with a recent version of Python."""
    sys.exit(1)

DEFAULT_HOST = 'localhost'
DEFAULT_PORT = '11211'

def main():
    usage = "%prog [opts] BUCKET_FILENAME (use -h for detailed help)"
    epilog = "Dump keys from Couchbase underlying SQLite data files."
    parser = optparse.OptionParser(usage=usage, epilog=epilog)
    parser.add_option("-a", "--all", action="store_true", default=False,
                      help="Dump all keys (no filter)")
    parser.add_option("-f", "--filter", default="",
                      help="Filter keys to print by regex")
    parser.add_option("-t", "--ttl", action="store_true", default=False,
                      help="Print TTL (expiry time) also")
    opts, args = parser.parse_args()

    if not (opts.all or opts.filter) or (opts.all and opts.filter):
        sys.exit("One of -f or -a must be specified")

    if len(args) != 1:
        parser.print_usage()
        sys.exit("A single bucket name argument is required")
    bucket_file = args[0]
    db_filenames = [bucket_file] + ["{0}-{1}.mb".format(bucket_file, i) for i in xrange(4)]
    for fn in db_filenames:
       if not os.path.isfile(fn):
          sys.exit("The file '{0}' doesn't exist".format(fn))

    # Attach all database files to a single connection
    # See http://www.sqlite.org/lang_attach.html
    db = sqlite3.connect(':memory:')
    attached_dbs = ["db{0}".format(i) for i in xrange(len(db_filenames))]
    db.executemany("ATTACH ? AS ?", zip(db_filenames, attached_dbs))

    # Find all the tables
    table_dbs = {}
    cur = db.cursor()
    for db_name in attached_dbs:
        cur.execute("SELECT name FROM %s.sqlite_master WHERE type = 'table'" % db_name)
        for (table_name,) in cur:
            table_dbs.setdefault(table_name, []).append(db_name)

    nodata = True
    for kv, dbs in table_dbs.iteritems():
        if 'kv_' in kv:
           nodata = False
           break
    if nodata:
        sys.exit("Data files contain no kv_* sqlite tables; maybe invalid backup files?")

    # Determine which db the state table is in; will error if there's more than
    # one
    try:
        (state_db,) = table_dbs[u'vbucket_states']
    except ValueError:
        sys.exit("Unable to locate unique vbucket_states table in database files")

    cur.execute("SELECT COUNT(*) FROM `{0}`.vbucket_states WHERE state LIKE 'active'".format(state_db))
    active_count, = cur.fetchone()
    if active_count == 0:
        sys.exit("No active vbuckets for {0} on this host".format(bucket_file))
    print >> sys.stderr, "Reading keys from {0} active vbuckets".format(active_count)

    # Print keys from active tables
    sql = """
        SELECT
            k, exptime
        FROM
            `{0}`.vbucket_states AS vb,
            `{{0}}` AS kv
        WHERE
            vb.state LIKE 'active'
            AND kv.vbucket = vb.vbid
            AND kv.vb_version = kv.vb_version
        ;
        """.format(state_db)

    filter = re.compile(opts.filter) if opts.filter else False

    print_format = "{0}\t{1}" if opts.ttl else "{1}"
    for kv, dbs in table_dbs.iteritems():
        if 'kv_' in kv:
            cur.execute(sql.format(kv))
            for k, exptime in cur:
                if not filter or re.search(filter, k):
                   print print_format.format(exptime, k)
            sys.stderr.write('.')
    sys.stderr.write('\n')

if __name__ == '__main__':
    main()
