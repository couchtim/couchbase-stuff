#! /usr/bin/perl

use strict;
use warnings;

use Time::Local qw/timegm/;

my $REGEXP = shift || '^ERROR';
my $GAPSIZE = readTime(shift || '5m');

print "Grouping when < ", niceTime($GAPSIZE), " between occurrences of /$REGEXP/\n";


my $firstSeenLine = 0;
my $firstSeenTime = 'NOTIME';
my $firstSeenSecs = 0;
my $prevSeenTime = 'NOTIME';
my $prevSeenLine = 0;
my $prevSeenSecs = 0;
my $nowTime = '';
my $seenSecs = 0;

my $currentCount = 0;

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

sub readTime {
	my ($str) = @_;
	my $seconds = 0;
	$str =~ s/^(\D+)// and warn "Ignoring extra stuff at start of time spec ('$1')\n";
	$seconds += $1 * 60 * 60 * 24 if $str =~ s/^(\d+)d//;
	$seconds += $1 * 60 * 60 if $str =~ s/^(\d+)h//;
	$seconds += $1 * 60 if $str =~ s/^(\d+)m//;
	$seconds += $1 if $str =~ s/^(\d+)s?//;
	warn "Ignoring extra stuff at end of time spec ('$str')\n" if $str;

	return $seconds;
}

sub niceTime {
	my ($secs) = @_;
	my $mins = int($secs / 60);
	$secs = $secs % 60;
	my $hours = int($mins / 60);
	$mins = $mins % 60;
	my $days = int($hours / 24);
	$hours = $hours % 24;
	my $nice;
	if ($hours) {
		if ($hours > 9) {
			my $fmt = $mins ? "%.1fh" : "%dh";
			$nice = sprintf $fmt, ($hours + $mins / 60);
		}
		else {
			$nice = sprintf "%dh%dm", $hours, $mins;
		}
	}
	elsif ($mins) {
		if ($mins > 9) {
			my $fmt = $secs ? "%.1fm" : "%dm";
			$nice = sprintf $fmt, ($mins + $secs / 60);
		}
		else {
			$nice = sprintf "%dm%ds", $mins, $secs;
		}
	}
	else {
		$nice = sprintf "%02ds", $secs;
	}

	return $nice;
}

while (<>) {
	if (/\b(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})$/) {
		print "START TIME: $1\n" unless $nowTime;
		$nowTime = $1
	}

	if (/$REGEXP/o) {
		my $secs = timeSecs($nowTime);
		# How long since the last time we saw it?
		my $diff = $secs - $seenSecs;
		$seenSecs = $secs;

		if ($diff > $GAPSIZE) {
			# Past a gap, print the previous block
			if ($currentCount) {
				printf "%7d-%7d (%s): %d times from $firstSeenTime to $prevSeenTime\n", $firstSeenLine, $prevSeenLine, niceTime($prevSeenSecs - $firstSeenSecs), $currentCount;
			}

			# Reset to this new block
			$currentCount = 0;
			$firstSeenSecs = $secs;
			$firstSeenTime = $nowTime;
			$firstSeenLine = $.;
		}

		++$currentCount;
		$prevSeenTime = $nowTime;
		$prevSeenSecs = $secs;
		$prevSeenLine = $.;
	}
}

# Once more at the end
if ($currentCount) {
	my $secs = timeSecs($nowTime);
	my $diff = $prevSeenSecs - $firstSeenSecs;
	printf "%7d-%7d (%s): %d times from $firstSeenTime to $prevSeenTime\n", $firstSeenLine, $prevSeenLine, niceTime($prevSeenSecs - $firstSeenSecs), $currentCount;
}

print "END TIME: $nowTime\n";

exit 0;
