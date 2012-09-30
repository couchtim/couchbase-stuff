#! /usr/bin/env python

import fileinput
from optparse import OptionParser
import sys

try:
    import mc_bin_client
except ImportError, e:
    print """Cannot find couchbase python libraries, please add it to PYTHONPATH
For example, this may work for most Unix users:
  export PYTHONPATH=/opt/couchbase/lib/python

"""
    raise

parser = OptionParser(usage = "Usage: %prog [options]")
# NB: required=True param breaks %prog --help
parser.add_option("-c", "--cluster", metavar="HOST:PORT")
parser.add_option("-b", "--bucket", metavar="BUCKET_NAME")
parser.add_option("-p", "--password", default="", metavar="BUCKET_PASSWORD")

(options, args) = parser.parse_args()

for opt in ["cluster", "bucket"]:
    if getattr(options, opt) is None:
        sys.stderr.write("Missing required --%s option\n" % (opt,))
        parser.print_help()
        sys.exit(1)

host, port = options.cluster.split(':')
port = int(port)

client = mc_bin_client.MemcachedClient(host, port)
client.sasl_auth_plain(options.bucket, options.password)

count = 0
errors = 0

for key in fileinput.input(args):
    key = key.rstrip('\n')
    try:
        client.delete(key)
        count += 1
    except mc_bin_client.MemcachedError, e:
        errors += 1
        print "DELETE ERROR '%s': %s" % (key, e)

print "Done (deleted %d keys)" % (count,)

if errors > 0:
    print "ERRORS: ", errors
    sys.exit(2)

sys.exit(0)
