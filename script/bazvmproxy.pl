#!/usr/bin/perl -w

use strict;
use warnings;
use Fcntl;		# for sysopen
use WWW::Curl::Easy;
use Sys::Syslog qw(:standard :macros);	# standard functions, plus macros
use File::Basename;
use POSIX qw(setsid);
use IO::Socket;

my $daemon_name = basename($0, '.pl');
my $daemon_pidfile;	# Will be filled in daemonize
my $daemon_running = 1;

# Our default configuration variables
our $baurl = "http://localhost/ba/";
our $downloaddir = "/tmp";
our $socketpath = "/var/run/" . $daemon_name . ".socket";
our $logmask = LOG_UPTO(LOG_INFO);
our $daemonize = 1;

# Initialize syslog and first part of daemonization
openlog($daemon_name, 'perror,pid', LOG_DAEMON);
chdir '/' or die "Can't chdir to /: $!";
umask 0;

# Read in (perl style) configuration file
my $confpath = "/etc/" . $daemon_name . ".conf";
if (-s $confpath) {
    syslog(LOG_INFO, "Using configuration file " . $confpath);
    do $confpath;
}

# logmask could have changed due to configuration file settings
setlogmask($logmask);
$ENV{PATH} .= ":/sbin";

my($socket, $msg, $MAXLEN);
$MAXLEN = 1024;

# $socketpath is not a socket but something else
unlink($socketpath) if (-S $socketpath);
if (-e $socketpath) {
    die "$0: won't overwrite " . $socketpath . "\n";
}

$socket = IO::Socket::UNIX->new(Local => $socketpath,
			      Type  => SOCK_DGRAM)
    or die "socket: $@";
syslog(LOG_DEBUG, "Awaiting messages on " . $socket->hostpath() . "\n");


# Callback signal handler for signals.
$SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signalHandler;
$SIG{PIPE} = 'ignore';

if ($daemonize) {
    open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
    open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
    open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";
    defined(my $pid = fork) or die "Can't fork: $!";
    exit if $pid;
    setsid or die "Can't start a new session: $!";

    # Create a PID file
    $daemon_pidfile = "/var/run/" . $daemon_name . ".pid";
    sysopen(PIDFILE, $daemon_pidfile, O_WRONLY | O_CREAT | O_EXCL, 0600)
	or die "Pid file already exists: " . $daemon_pidfile . "\n";

    print PIDFILE $$;
    close(PIDFILE);
}

while ($daemon_running) {
    # exit if socket manually removed
    die "SOCKET disappeared: " . $socketpath unless -S $socketpath;
    syslog(LOG_DEBUG, "Waiting for SMSG event\n");

    # next line blocks until there's an event
    if(!defined($socket->recv($msg, $MAXLEN, 0))) {
	if ($! =~ /Interrupted system call/) {
	    next;
	}
	die "can't recv from $socketpath: $!";
    }

    my ($header, $kv) = split(chr(0), $msg, 2);
    my %values = split(/[=\0]/, $kv);

    my $line = join(' ', $values{'SMSG_SENDER'}, $values{'SMSG_ID'},
		    $values{'SMSG_TEXT'});
    syslog(LOG_DEBUG, "SMSG Payload: " . $line);
    process_smsg_event($line);

    select(undef, undef, undef, 0.2);  # sleep 1/5th second
}

syslog(LOG_INFO, "Exiting\n");
closelog();


sub process_smsg_event
{
    my($line) = @_;

    my @tokens = split(/ /, $line);
    my @macs = split(",", $tokens[2]);

    foreach my $mac (@macs) {
	my $punched = 0;

	# z/VM is using "-" as a separator
	$mac =~ s/-/:/g;

	syslog(LOG_INFO, "%s: Processing MAC %s\n", $tokens[0], $mac);

	if (fetch_images($tokens[0], $mac,
			 my @images = ('linux', 'parm', 'initrd')) == 0) {
	    syslog(LOG_INFO, "%s: Punching images %s\n", $tokens[0],
		   join(' ', @images));

	    foreach my $image (@images) {
		my @args = ("/usr/sbin/vmur",
			    "punch", "--rdr", "--user", $tokens[0],
			    get_downloadpath($tokens[0], $image),
			    "--name",
			    get_imagename($tokens[0], $image));
		syslog(LOG_DEBUG, join(' ', @args) . "\n");
		system(@args);
		if ($? & 127) {
		    syslog(LOG_CRIT,
			   "child died with signal %d, %s coredump\n",
			   ($? & 127), ($? & 128) ? 'with' : 'without');
		    goto ERROR_NEXT;
		} elsif ($? != 0) {
		    syslog(LOG_ERR, "failed to execute: $!\n");
		    goto ERROR_NEXT;
		}
	    }

	    $punched = 1;
	}

#	if (fetch_images($tokens[0], $mac, my @images = ('exec')) == 0) {
#	    syslog(LOG_INFO, "Not implemented yet!\n");
#	    goto SUCCESS_NEXT;
#	}
	#
	# If we successfully punched something but failed to download a
	# guest REXX script we want to IPL the guest from the reader
	#
#	elsif ($punched) {
	if ($punched) {
	    syslog(LOG_INFO, "%s: IPL guest from RDR\n", $tokens[0]);
	    my @args = ("/sbin/vmcp", "send", $tokens[0],
			"#CP IPL 00c");
	    syslog(LOG_DEBUG, join(' ', @args) . "\n");
	    system(@args);
	    if ($? & 127) {
		syslog(LOG_CRIT, "child died with signal %d, %s coredump\n",
		       ($? & 127), ($? & 128) ? 'with' : 'without');
	    } elsif ($? != 0) {
		syslog(LOG_ERR, "failed to execute: $!\n");
	    }
	    goto SUCCESS_NEXT;
	}
    } # @macs

    #
    # If we are here none of the MACs was registered with Baracus.
    #
    my @args = ("/sbin/vmcp", "send", $tokens[0], "#CP LOGOFF");
    syslog(LOG_DEBUG, join(' ', @args) . "\n");
    system(@args);
    if ($? & 127) {
	syslog(LOG_CRIT, "child died with signal %d, %s coredump\n",
	       ($? & 127), ($? & 128) ? 'with' : 'without');
    } elsif ($? != 0) {
	syslog(LOG_ERR, "failed to execute: $!\n");
    }

    next;
  ERROR_NEXT:
    syslog(LOG_DEBUG, "Abort! Next try\n");
  SUCCESS_NEXT:
}

#
#curl -o s390s03.linux  http://baracus/ba/linux?mac=<mac>
#curl -o s390s03.initrd http://baracus/ba/initrd?mac=<mac>
#
sub mycurl
{
    my($url, $filename) = @_;

    # Setting the options
    my $curl = new WWW::Curl::Easy;

    $curl->setopt(CURLOPT_HEADER,0);
    $curl->setopt(CURLOPT_URL, $url);
    my $response_body;

    # NOTE - do not use a typeglob here.
    # A reference to a typeglob is okay though.
    syslog(LOG_DEBUG, "Writing to %s\n", $filename);
    open (my $fileb, ">" . $filename);
    $curl->setopt(CURLOPT_WRITEDATA,$fileb);

    # Starts the actual request
    my $retcode = $curl->perform;

    # Looking at the results...
    if ($retcode == 0) {
	my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
	syslog(LOG_DEBUG, "Status: %d, URL: %s\n", $response_code,
	       $curl->getinfo(CURLINFO_EFFECTIVE_URL));
	# judge result and next action based on $response_code
	if (($response_code < 200) || ($response_code >= 300)) {
	    return $response_code
	}
    } else {
	syslog(LOG_ERR, "An error happened: " .
	       $curl->strerror($retcode) ." ($retcode)\n");
    }

    return $retcode
}

sub get_imagename
{
    my($userid, $image) = @_;
    my %imagenames = ("linux", "image");

    if (exists($imagenames{$image})) {
	return $userid . "." . $imagenames{$image};
    } else {
	return $userid . "." . $image;
    }
}

sub get_downloadpath
{
    my($userid, $image) = @_;
    return $downloaddir . "/" . get_imagename($userid, $image);
}

#
# Download the necessary images for punching them to the reader later
#
# Globals used:
# - $baurl
#
sub fetch_images
{
    my($userid, $mac, @images) = @_;
    my $retval = 0;

    foreach my $image (@images) {
	syslog(LOG_DEBUG, "Getting " . $image . "\n");
	$retval = mycurl($baurl . $image . "?mac=" . $mac,
			 get_downloadpath($userid, $image));
	if ($retval != 0) {
	    return $retval;
	}
    }
}

# catch signals and end the program if one is caught.
sub signalHandler {
    $daemon_running = 0;
}

# do this stuff when exit() is called.
END {
    if($daemon_pidfile) {
	unlink($daemon_pidfile);
    }
}