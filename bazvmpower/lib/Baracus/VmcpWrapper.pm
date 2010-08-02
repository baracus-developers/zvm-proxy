package Baracus::VmcpWrapper;
require Exporter;
use POSIX;

@ISA = qw(Exporter);
@EXPORT = qw(power);

# on:     logging the guest
# off:    logoff the guest
# cycle:  give the VM 60 seconds to shutdown properly
# status: query the guest (returns error #45 if guest is not online)
my %operations = (
    'on'     => '/sbin/vmcp xautolog %s',
    'off'    => '/sbin/vmcp send %s \'#CP LOGOFF\'',
    'cycle'  => '/sbin/vmcp send %s \'#CP SIGNAL SHUTDOWN WITHIN 60\'',
    'status' => '/sbin/vmcp query %s',
    );

my %responses = (
    'on'     => 'Online',
    'off'    => 'Offline',
    'cycle'  => 'Online',
    'status' => 'Online',
    );

sub run_command
{
    local($command) = @_;
    local(@result, @contents, $pid);

    # Dancer: do not automatically reap this child
    local $savesig = $SIG{CHLD};
    $SIG{CHLD} = 'DEFAULT';

    $pid = open(PIPE, $command . ' |');
    unless (defined $pid) {
	die "Cannot fork: $!";
    }

    while (<PIPE>) {
	push @contents, $_;
    }

    close(PIPE);

    $result[0] = join("\n", @contents);
    $result[1] = $?;

    if (WIFEXITED($?)) {
	if (WEXITSTATUS($?) == 126) {
	    # EPERM
	    $! = 1;
	} elsif (WEXITSTATUS($?) == 127) {
	    # ENOENT
	    $! = 2;
	}
	$result[1] = WEXITSTATUS($?);
	$result[2] = $!;
    }

    # Restore original signal setting
    $SIG{CHLD} = $savesig;
    return @result;
}

# "Usage: $0 <operation> <guestname>\n";
# "    e.g. operation = 'status'\n";
# "         guestname = 'LINUX101'\n";
sub power
{
    local($operation, $hostname) = @_;
    local($command, $result, $retval, $errval);

    die "Invalid argument: '" . join(" ", @_) . "'"
	unless ((scalar(@_) == 2) && grep(/$operation/,keys(%operations)));

    $command = sprintf( $operations{ $operation }, $hostname );

    $command .= " 2>/dev/null";
    ($result, $retval, $errval) = run_command($command);
    if ($retval == -1) {
	die "Error running '$command': ($retval) $errval";
    } elsif ( $retval == 0 ) {
	return $responses{$operation};
    } elsif ( $retval == 1 ) {
	# Normal termination
	$result =~ m/^HCP(CQU|SEC)(\d+)E.*/;
	if ( defined($2) && $2 == 45 ) {
	    return "Offline" unless ($operation eq "cycle");
	}
	chomp($result);
	die ($result || "Unknown error: ($retval) $errval");
    } else {
	chomp($result);
	die ($result || "Unknown error: ($retval) $errval");
    }

    return;
}

1;
