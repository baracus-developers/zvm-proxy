#use strict;
#use warnings;
use Fcntl;             # for sysopen
use WWW::Curl::Easy;

chdir;                 # go home
my $baurl = "http://151.155.230.38/ba/";
my $downloaddir = "/tmp";
$fpath = '.signature';
$ENV{PATH} .= ":/usr/games";

unless (-p $fpath) {   # not a pipe
    if (-e _) {        # but a something else
        die "$0: won't overwrite .signature\n";
    } else {
        require POSIX;
        POSIX::mkfifo($fpath, 0666) or die "can't mknod $fpath: $!";
        warn "$0: created $fpath as a named pipe\n";
    }
}

#
#curl -o s390s03.linux  http://baracus/ba/linux?mac=<mac>
#curl -o s390s03.initrd http://baracus/ba/initrd?mac=<mac>
#

while (1) {
    # exit if signature file manually removed
    die "Pipe file disappeared" unless -p $fpath;
    print "Next try\n";
    # next line blocks until there's a reader
    sysopen(FIFO, $fpath, O_RDONLY)
        or die "can't write $fpath: $!";
  OUTER_REDO:
    while (my $line = <FIFO>) {
	print STDERR $line;
	@tokens = split(/ /, $line);
	@macs = split(",", $tokens[2]);
	my $mac = $macs[0];
	$mac =~ s/-/:/g;
	print STDERR "Processing MAC " . $mac . "\n";

	# Download all the images for this guest
#	my @images = ('linux', 'initrd', 'parm', 'exec');
	my @images = ('linux', 'initrd');
	foreach my $image (@images) {
	    print STDERR "Getting " . $image . "\n";
	    mycurl($baurl . $image . "?mac=" . $mac,
		   $downloaddir . "/" . $tokens[0] . "." . $image);
	    if ($? != 0) {
		goto OUTER_REDO;
	    }
	}

	# Do the thing we need to do for the guest
	@images = ('linux', 'parm', 'initrd');
	foreach my $image (@images) {
	    my @args = ("/usr/sbin/vmur",
			"punch", "--rdr", "--user", $tokens[0],
			$downloaddir . "/" . $tokens[0] . "." . $image,
			"--name", $tokens[0] . "." . $image);
	    print STDERR join(' ', @args) . "\n";
	    system(@args);
	    if ($? & 127) {
		printf STDERR "child died with signal %d, %s coredump\n",
		($? & 127), ($? & 128) ? 'with' : 'without';
		goto OUTER_REDO;
	    }
	    elsif ($? != 0) {
		print STDERR "failed to execute: $!\n";
		goto OUTER_REDO;
	    }
	}

	# IPL the guest from the reader
	my @args = ("/sbin/vmcp", "send", $tokens[0], "#CP IPL 00c");
	print STDERR join(' ', @args) . "\n";
	system(@args);
	if ($? & 127) {
	    printf STDERR "child died with signal %d, %s coredump\n",
	    ($? & 127), ($? & 128) ? 'with' : 'without';
	}
	elsif ($? != 0) {
	    print STDERR "failed to execute: $!\n";
	}
    }
    close FIFO;
    select(undef, undef, undef, 0.2);  # sleep 1/5th second
}

sub mycurl {
    my($url, $filename) = @_;

    # Setting the options
    my $curl = new WWW::Curl::Easy;

#    $curl->setopt(CURLOPT_HEADER,1);
    $curl->setopt(CURLOPT_HEADER,0);
    $curl->setopt(CURLOPT_URL, $url);
    my $response_body;

    # NOTE - do not use a typeglob here.
    # A reference to a typeglob is okay though.
#    open (my $fileb, ">", \$response_body);
    print STDERR "Writing to " . $filename . "\n";
    open (my $fileb, ">" . $filename);
    $curl->setopt(CURLOPT_WRITEDATA,$fileb);

    # Starts the actual request
    my $retcode = $curl->perform;

    # Looking at the results...
    if ($retcode == 0) {
	print STDERR "Transfer went ok\n";
	my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
	# judge result and next action based on $response_code
#	print("Received response: $response_body\n");
    } else {
	print STDERR "An error happened: ".$curl->strerror($retcode)." ($retcode)\n";
    }

    return $retcode
}
