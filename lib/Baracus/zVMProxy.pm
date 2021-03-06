package Baracus::zVMProxy;

use 5.010000;
use strict;
use warnings;

require Exporter;

use Fcntl;		# for sysopen
use WWW::Curl::Easy;
use Sys::Syslog qw(:standard :macros);	# standard functions, plus macros
use POSIX qw(setsid);
use IO::Socket;

our @ISA = qw(Exporter);

# Items to export into callers namespace by default. Note: do not export
# names by default without a very good reason. Use EXPORT_OK instead.
# Do not simply export all your public functions/methods/constants.

# This allows declaration	use Baracus::zVMProxy ':all';
# If you do not need this, moving things directly into @EXPORT or @EXPORT_OK
# will save memory.
our %EXPORT_TAGS = ( 'all' => [ qw(
	run
) ] );

our @EXPORT_OK = ( @{ $EXPORT_TAGS{'all'} } );

our @EXPORT = qw(
	
);

our $VERSION = '0.01';

our $daemon_name = 'bazvmproxy';
our $daemon_pidfile;	# Will be filled in daemonize
our $daemon_pid;	# Will be filled in daemonize
our $daemon_running = 1;

# Our default configuration variables
our $baurl = "http://localhost/ba/";
our $downloaddir = "/tmp";
our $socketpath = "/var/run/%s.socket";
our $logmask = LOG_UPTO(LOG_INFO);
our $daemonize = 0;

# Preloaded methods go here.

sub crit
{
    if ($daemonize) {
	syslog(LOG_CRIT, @_);
    } else {
	my ($format, @args) = @_;
	printf STDERR "CRIT: " . $format, @args;
    }
}

sub err
{
    if ($daemonize) {
	syslog(LOG_ERR, @_);
    } else {
	my ($format, @args) = @_;
	printf STDERR "ERROR: " . $format, @args;
    }
}

sub info
{
    if ($daemonize) {
	syslog(LOG_INFO, @_);
    } else {
	my ($format, @args) = @_;
	printf STDERR "INFO: " . $format, @args;
    }
}

sub debug
{
    if ($daemonize) {
	syslog(LOG_DEBUG, @_);
    } else {
	my ($format, @args) = @_;
	printf STDERR "DEBUG: " . $format, @args;
    }
}


sub process_smsg_event
{
    my($line) = @_;

    my @tokens = split(/ /, $line);
    my @macs = split(",", $tokens[2]);

    foreach my $mac (@macs) {
	my $punched = 0;

	# z/VM is using "-" as a separator
	$mac =~ s/-/:/g;

	info("%s: Processing MAC %s\n", $tokens[0], $mac);

	if (fetch_images($tokens[0], $mac,
			 my @images = ('linux', 'parm', 'initrd')) == 0) {
	    info("%s: Punching images %s\n", $tokens[0],
		   join(' ', @images));

	    foreach my $image (@images) {
		my @args = ("/usr/sbin/vmur",
			    "punch", "--rdr", "--user", $tokens[0],
			    get_downloadpath($tokens[0], $image),
			    "--name",
			    get_imagename($tokens[0], $image));
		debug(join(' ', @args) . "\n");
		system(@args);
		if ($? & 127) {
		    crit("child died with signal %d, %s coredump\n",
			 ($? & 127), ($? & 128) ? 'with' : 'without');
		    goto ERROR_NEXT;
		} elsif ($? != 0) {
		    err("failed to execute: $!\n");
		    goto ERROR_NEXT;
		}
	    }

	    $punched = 1;
	}

	#
	# If we successfully punched something we want to IPL from the reader
	#
	if ($punched) {
	    info("%s: IPL guest from RDR\n", $tokens[0]);
	    my @args = ("/sbin/vmcp", "send", $tokens[0],
			"#CP IPL 00c");
	    debug(join(' ', @args) . "\n");
	    system(@args);
	    if ($? & 127) {
		crit("child died with signal %d, %s coredump\n",
		       ($? & 127), ($? & 128) ? 'with' : 'without');
	    } elsif ($? != 0) {
		err("failed to execute: $!\n");
	    }
	    goto SUCCESS_NEXT;
	}
	#
	# Fetch guest specific REXX script and execute it
	#
	elsif (fetch_images($tokens[0], $mac, my @images = ('exec')) == 0) {
	    info("%s: Punching files %s\n", $tokens[0],
		   join(' ', @images));

	    foreach my $image (@images) {
		my @args = ("/usr/sbin/vmur",
			    "punch", "--rdr", "--user", $tokens[0],
			    get_downloadpath($tokens[0], $image),
			    "--text",
			    "--name",
			    uc(get_imagename($tokens[0], $image)));
		debug(join(' ', @args) . "\n");
		system(@args);
		if ($? & 127) {
		    crit("child died with signal %d, %s coredump\n",
			 ($? & 127), ($? & 128) ? 'with' : 'without');
		    goto ERROR_NEXT;
		} elsif ($? != 0) {
		    err("failed to execute: $!\n");
		    goto ERROR_NEXT;
		}
	    }

	    # Reorder files in remote reader: bring EXEC to front
	    my @args = ("/sbin/vmcp", "send", $tokens[0],
			"'PIPE CP Q RDR ALL | drop | l 54." .
			(length($tokens[0])+1) . " /" . $tokens[0] .
			" / | l 64.5 /EXEC / | split | drop | take | " .
			"preface literal order reader | join / / | cp'");
	    debug(join(' ', @args) . "\n");
	    system(@args);
	    if ($? & 127) {
		crit("child died with signal %d, %s coredump\n",
		     ($? & 127), ($? & 128) ? 'with' : 'without');
		goto ERROR_NEXT;
	    } elsif ($? != 0) {
		err("failed to execute: $!\n");
		goto ERROR_NEXT;
	    }

	    # Execute REXX script
	    @args = ("/sbin/vmcp", "send", $tokens[0],
		     'PIPE reader | spec 2-* 1 | drop 1 | rexx *: ');
	    debug(join(' ', @args) . "\n");
	    system(@args);
	    if ($? & 127) {
		crit("child died with signal %d, %s coredump\n",
		     ($? & 127), ($? & 128) ? 'with' : 'without');
		goto ERROR_NEXT;
	    } elsif ($? != 0) {
		err("failed to execute: $!\n");
		goto ERROR_NEXT;
	    }

	    goto SUCCESS_NEXT;
	}

      ERROR_NEXT:
    } # @macs

    #
    # If we are here none of the MACs was registered with Baracus.
    #
    debug("Logoff guest $tokens[0]\n");
    my @args = ("/sbin/vmcp", "send", $tokens[0], "#CP LOGOFF");
    debug(join(' ', @args) . "\n");
    system(@args);
    if ($? & 127) {
	crit("child died with signal %d, %s coredump\n",
	       ($? & 127), ($? & 128) ? 'with' : 'without');
    } elsif ($? != 0) {
	err("failed to execute: $!\n");
    }

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
    debug("Writing to %s\n", $filename);
    open (my $fileb, ">" . $filename);
    $curl->setopt(CURLOPT_WRITEDATA,$fileb);

    # Starts the actual request
    my $retcode = $curl->perform;

    # Looking at the results...
    if ($retcode == 0) {
	my $response_code = $curl->getinfo(CURLINFO_HTTP_CODE);
	debug("Status: %d, URL: %s\n", $response_code,
	       $curl->getinfo(CURLINFO_EFFECTIVE_URL));
	# judge result and next action based on $response_code
	if (($response_code < 200) || ($response_code >= 300)) {
	    return $response_code
	}
    } else {
	err("An error happened: " .
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
	debug("Getting " . $image . "\n");
	$retval = mycurl($baurl . $image . "?mac=" . $mac . "&node=" . $userid,
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

sub run {

    if (defined $_[0]) {
	$daemon_name = $_[0];
    }

    # Initialize syslog and first part of daemonization
    openlog($daemon_name, 'perror,pid', LOG_DAEMON);
    chdir '/' or die "Can't chdir to /: $!";
    umask 0;

    # Read in (perl style) configuration file
    my $confpath = "/etc/" . $daemon_name . ".conf";
    if (-s $confpath) {
	info("Using configuration file '$confpath'\n");
	do $confpath;
    }

    # logmask could have changed due to configuration file settings
    setlogmask($logmask);
    $ENV{PATH} .= ":/sbin";

    # In case the daemon dies we still want to see the message
    if ($daemonize) {
	$SIG{__DIE__} = sub {
	    syslog(LOG_CRIT, @_);
	};
    }

    my($socket, $msg, $MAXLEN);
    $MAXLEN = 1024;

    # $socketpath is not a socket but something else
    $socketpath = sprintf($socketpath, $daemon_name);
    unlink($socketpath) if (-S $socketpath);
    if (-e $socketpath) {
	die "$0: won't overwrite " . $socketpath . "\n";
    }

    $socket = IO::Socket::UNIX->new(Local => $socketpath,
				    Type  => SOCK_DGRAM)
	or die "Can't create socket '$socketpath': $!";
    debug("Awaiting messages on " . $socket->hostpath() . "\n");


    # Callback signal handler for signals.
    $SIG{INT} = $SIG{TERM} = $SIG{HUP} = \&signalHandler;
    $SIG{PIPE} = 'ignore';

    if ($daemonize) {
	# Create the .pid file before we fork in case something goes wrong
	my $pidfile = "/var/run/" . $daemon_name . ".pid";
	sysopen(PIDFILE, $pidfile, O_WRONLY | O_CREAT | O_EXCL, 0600)
	    or die "Can not create pid file ('$pidfile'): $!\n";

	$daemon_pidfile = $pidfile;

	open STDIN, '/dev/null' or die "Can't read /dev/null: $!";
	open STDOUT, '>/dev/null' or die "Can't write to /dev/null: $!";
	open STDERR, '>/dev/null' or die "Can't write to /dev/null: $!";
	defined(my $pid = fork) or die "Can't fork: $!";
	exit if $pid;
	$daemon_pid = $$;
	setsid or die "Can't start a new session: $!";

	# write daemon PID to the .pid file
	print PIDFILE $$;
	close(PIDFILE);
    }

    while ($daemon_running) {
	# exit if socket manually removed
	die "SOCKET disappeared: " . $socketpath unless -S $socketpath;
	debug("Waiting for SMSG event\n");

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
	debug("SMSG Payload: " . $line);
	process_smsg_event($line);

	select(undef, undef, undef, 0.2);  # sleep 1/5th second
    }

    info("Exiting\n");
    closelog();
}

END {
    if ($$ == $daemon_pid && $daemon_pidfile) {
	debug("Removing .pid file '$daemon_pidfile'\n");
	unlink($daemon_pidfile);
    }
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Baracus::zVMProxy - Perl extension for blah blah blah

=head1 SYNOPSIS

  use Baracus::zVMProxy;
  blah blah blah

=head1 DESCRIPTION

Stub documentation for Baracus::zVMProxy, created by h2xs. It looks like the
author of the extension was negligent enough to leave the stub
unedited.

Blah blah blah.

=head2 EXPORT

None by default.



=head1 SEE ALSO

Mention other useful documentation such as the documentation of
related modules or operating system documentation (such as man pages
in UNIX), or any relevant external documentation such as RFCs or
standards.

If you have a mailing list set up for your module, mention it here.

If you have a web site set up for your module, mention it here.

=head1 AUTHOR

Jan Blunck, E<lt>jblunck@(none)E<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jan Blunck

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
