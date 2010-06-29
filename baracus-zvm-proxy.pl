use strict;
use warnings;
use Fcntl;		# for sysopen
use WWW::Curl::Easy;
use Sys::Syslog qw(:standard :macros);	# standard functions, plus macros

my $baurl = "http://151.155.230.38/ba/";
my $downloaddir = "/tmp";
my $fpath = '/tmp/.Baracus-zVM';
$ENV{PATH} .= ":/usr/games";

# Initialize daemon
openlog("bazvmproxy.pl $$", 'perror,pid', LOG_DAEMON);
chdir '/' or die "Can't chdir to /: $!";

unless (-p $fpath) {   # not a pipe
    if (-e _) {        # but a something else
	die "$0: won't overwrite " . $fpath . "\n";
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
    # exit if fifo file manually removed
    die "FIFO file disappeared: " . $fpath unless -p $fpath;
    syslog(LOG_DEBUG, "Waiting for SMSG\n");
    # next line blocks until there's a reader
    sysopen(FIFO, $fpath, O_RDONLY)
	or die "can't write $fpath: $!";
    while (my $line = <FIFO>) {
	syslog(LOG_DEBUG, "SMSG Payload: " . $line);
	my @tokens = split(/ /, $line);
	my @macs = split(",", $tokens[2]);
	my $mac = $macs[0];
	$mac =~ s/-/:/g;
	syslog(LOG_INFO, "Processing MAC: " . $mac . "\n");

	# Download all the images for this guest
#	my @images = ('linux', 'initrd', 'parm', 'exec');
	my @images = ('linux', 'parm', 'initrd');
	foreach my $image (@images) {
	    syslog(LOG_DEBUG, "Getting " . $image . "\n");
	    my $ret = mycurl($baurl . $image . "?mac=" . $mac,
			     $downloaddir . "/" . $tokens[0] . "." . $image);
	    if ($ret != 0) {
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
	    syslog(LOG_DEBUG, join(' ', @args) . "\n");
	    system(@args);
	    if ($? & 127) {
		syslog(LOG_CRIT, "child died with signal %d, %s coredump\n",
		       ($? & 127), ($? & 128) ? 'with' : 'without');
		goto OUTER_REDO;
	    }
	    elsif ($? != 0) {
		syslog(LOG_ERR, "failed to execute: $!\n");
		goto OUTER_REDO;
	    }
	}

	# IPL the guest from the reader
	my @args = ("/sbin/vmcp", "send", $tokens[0], "#CP IPL 00c");
	syslog(LOG_DEBUG, join(' ', @args) . "\n");
	system(@args);
	if ($? & 127) {
	    syslog(LOG_CRIT, "child died with signal %d, %s coredump\n",
		   ($? & 127), ($? & 128) ? 'with' : 'without');
	}
	elsif ($? != 0) {
	    syslog(LOG_ERR, "failed to execute: $!\n");
	}

	# while
	next;
      OUTER_REDO:
	syslog(LOG_DEBUG, "Abort! Next try\n");
    }
    close FIFO;
    select(undef, undef, undef, 0.2);  # sleep 1/5th second
}

closelog();

sub mycurl
{
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
    syslog(LOG_DEBUG, "Writing to " . $filename . "\n");
    open (my $fileb, ">" . $filename);
    $curl->setopt(CURLOPT_WRITEDATA,$fileb);

    # Starts the actual request
    my $retcode = $curl->perform;

    # Looking at the results...
    if ($retcode == 0) {
	my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
	# judge result and next action based on $response_code
	if (($response_code < 200) || ($response_code >= 300)) {
	    syslog(LOG_DEBUG, "Received response: $response_code\n");
	    return $response_code
	}
	syslog(LOG_DEBUG, "Transfer went ok\n");
    } else {
	syslog(LOG_ERR, "An error happened: " .
	       $curl->strerror($retcode) ." ($retcode)\n");
    }

    return $retcode
}
