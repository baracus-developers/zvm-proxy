#!/usr/bin/perl -w

BEGIN {
    push @INC,"/home/jblunck/Export/Baracus/baracus-zvm-proxy/bazvmpower/lib";
}

use VmcpWrapper;

if (scalar(@ARGV) != 2) {
    print "Usage: $0 <operation> <guestname>\n";
    exit(1);
}

print "Result: " . power($ARGV[0], $ARGV[1]) . "\n";
