#! /usr/bin/env perl

# Tool with minimal dependencies to grab list of keys from a node
# which match a regex. To be used with another tool to process
# these keys (delete them, for example). Pipe output of this
# into another tool, or save to a file and process, etc.

# Designed with minimal external dependencies, only requires the
# sqlite3 command line tool that is shipped with Couchbase Server,
# and Perl (usually pre-installed on all server OS).

my $sqlite = '/opt/couchbase/bin/sqlite3';
-x $sqlite or die "Can't find sqlite command-line executable at '$sqlite'";

my $bucket = shift;
unless (defined $bucket) {
    print <<EOF;
Usage: $0 /path/to/bucket-data/bucket [filter-regex]

Dumps keys stored in active vbuckets on this node for a given
bucket. Pass the full path to the main bucket data file.  No
passwords are needed, since this reads directly from the
underlying data files on disk.

Keys are hex-encoded to ensure no possible confusion with
non-ASCII characters, whitespace, etc.

If a filter-regex is supplied, only print keys which match it.


Dump all keys from the default bucket:
    $0 /opt/couchbase/var/lib/couchbase/data/default-data/default

Dump keys starting with 'foo_bar' from bucket 'a_bucket':
    $0 /opt/couchbase/var/lib/couchbase/data/a_bucket-data/a_bucket '^foo_bar'
EOF
    exit 1
}
-r $bucket or die "Can't read database file '$bucket'";

my $filter = shift;

my $errors = 0;
my @active = `"$sqlite" "$bucket" 'SELECT vbid FROM vbucket_states WHERE state LIKE "active"'`;
chomp @active;

unless (@active) {
    ++$errors;
    warn "ERROR on bucket $bucket, no active vbuckets: $!\n";
}

print STDERR "Active vbuckets: @active\n";
my $total_items = 0;
my $matched_items = 0;
my $vbucket_progress = 0;
for my $part (0, 1, 2, 3) {
    # Process each bucket-{0,1,2,3}.mb file in turn, to
    # take more advantage of filesystem buffer
    for my $vbid (@active) {
        next unless $vbid % 4 == $part;
        ++$vbucket_progress;
        my $file = "$bucket-$part.mb";
        unless (open RESULTS, "$sqlite $file 'SELECT hex(k) FROM kv_$vbid' |") {
            ++$errors;
            warn "ERROR on bucket file $file, vbucket $vbid, dump may be incomplete: $!\n";
            next;
        }
        while (<RESULTS>) {
            ++$total_items;
            chomp;
            my $key = unhex($_);
            unless (defined $filter and $key !~ /$filter/o) {
                ++$matched_items;
                print "$_\n";  # Print in HEX format for safety
            }
            printf STDERR "%2d%% matched %d / seen %d items  # vbucket: %d (%d/%d)\n",
                    int($vbucket_progress / scalar(@active) * 100),
                    $matched_items, $total_items, $vbid, $vbucket_progress, scalar(@active)
                if $total_items % 50_000 == 0;
        }
        unless (close RESULTS) {
            ++$errors;
            warn "ERROR on bucket file $file, vbucket $vbid, dump may be incomplete: $!\n";
        }
    }
}

print STDERR "# Done.\n";

exit(2) if ($errors);
exit(0);

sub unhex {
    my ($str) = @_;
    $str =~ s/(..)/chr(hex($1))/eg;
    return $str;
}
