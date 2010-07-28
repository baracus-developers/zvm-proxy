#!/usr/bin/perl -w

BEGIN {
    push @INC,"./lib";
}

use Baracus::VmcpWrapper;

if (scalar(@ARGV) != 2) {
    print STDERR "Usage: $0 <operation> <guestname>\n";
    print STDERR "    e.g. operation = 'status'\n";
    print STDERR "         guestname = 'LINUX101'\n";
    exit(1);
}

eval {
    my $result = power($ARGV[0], $ARGV[1]);
    if(defined($result)) {
	print "Result: $result\n";
    }
    1;
} or do {
    print STDERR ( $@ || "Unknown error!\n" );
}
