#! /usr/bin/env python

import sys
import fileinput

try:
    import mc_bin_client
except ImportError, e:
    print """Cannot find couchbase python libraries, please add it to PYTHONPATH
For example, this may work for most Unix users:
  export PYTHONPATH=/opt/couchbase/lib/python

"""
    raise

db = mc_bin_client.MemcachedClient('10.4.2.14', 11211)

count = 0

for key in fileinput.input():
    key = key.rstrip('\n')
    try:
        db.delete(key)
        count += 1
    except mc_bin_client.MemcachedError, e:
        print "DELETE ERROR '%s': %s" % (key, e)

print "Done (deleted %d keys)" % (count,)
