#! /usr/bin/env perl

use strict;
use warnings;

use Time::Local qw/timegm/;

sub timeSecs {
	my ($theTime) = @_;
	unless ($theTime) {
		warn "timeSecs() called w/ empty time string";
		return -1;
	}

	my ($date, $time) = split(/ /, $theTime);
	my ($y, $m, $d) = split(/-/, $date);
	my ($H, $M, $S) = split(/:/, $time);
	return timegm($S, $M, $H, $d, $m - 1, $y);
}

my $in_block = 0;
# INFO REPORT, ERROR REPORT, and CRASH REPORT, most likely
my $block_header_regex = qr/^([A-Z]+) REPORT +<[\d.]+> +(\d{4}-\d{2}-\d{2} [\d:]{8})$/;

# In some cases, we want to print a block only if the following block
# contains certain text -- yech. So keep a pointer to the previous block
# around in case it's needed.
my $previous_block = undef;
my $block = [];

my $hack = 0;
while (<>) {
    s/\r?\n$//;
    if (/$block_header_regex/) {
        finish_block();  # Handle the previous block, if any
        $in_block = 1;
        add_block_line($_);
    }
    elsif ($in_block) {
        add_block_line($_);
    }
}

finish_block();

exit 0;


sub add_block_line {
    my ($line) = @_;
    push @$block, $line;
}

sub finish_block {
    if ($block and @$block > 2) {
        my $print_it = 1;

        $print_it = 0
            if $block->[0] =~ /^INFO /
                or @$block > 3 and (
                       $block->[3] =~ /:stats_collector:\d+: Dropped \d+ tick/
                    or $block->[3] =~ /:system_stats_collector:\d+: lost \d+ tick/
                    or $block->[3] =~ /:stats_reader:\d+: Some nodes didn't respond:/
                    or $block->[3] =~ /Failed to grab system stats/
                    or $block->[3] =~ /Mnesia is overloaded/
                    or $block->[3] =~ /Mnesia detected overload/
#                    or $block->[2] =~ /^supervisor/ and $block->[3] =~ /^started/
#                    or @$block > 8 and $block->[5] =~ /errorContext +child_terminated/ and $block->[8] =~ /name +hot_keys_keeper/
                )
                # This is an intentional crash, causes the ebucket migrator
                # to retry later; will be flagged differently in 1.8.1
                or (grep { /retry_not_ready_vbuckets/ } @$block)
                ;

        if (@$block > 3 and $block->[3] =~ /Dropped \d+ log lines from memcached/) {
            print @$previous_block;
        }

        if ($print_it) {
            print "$_\n" for @$block;
        }
    }

    $previous_block = $block;
    $block = [];
}
