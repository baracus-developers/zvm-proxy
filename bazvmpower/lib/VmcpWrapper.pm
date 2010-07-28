package VmcpWrapper;
require Exporter;

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

sub run_command
{
    local($command) = @_;
    local(@result);

    $result[0] = `$command`;
    $result[1] = $?;
    $result[2] = $!;
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

    if ( $operation eq "status") {
	$command .= " 2>/dev/null";
	($result, $retval, $errval) = run_command($command);
	if ($retval == -1) {
	    die "Error running '$command': $errval";
	} elsif ( $retval == 0 ) {
	    return "Online";
	} elsif ( $retval == 256 ) {
	    # Normal termination, WEXITSTATUS($?) == 1
	    $result =~ m/^HCPCQU(\d+)E.*/;
	    if ( defined($1) && $1 == 45 ) {
		return "Offline";
	    } else {
		chomp($result);
		die ($result || "Unknown error");
	    }
	} else {
	    chomp($result);
	    die ($result || "Unknown error");
	}
    } else {
	$command .= " 2>&1";
	($result, $retval, $errval) = run_command($command);
	if ($retval == -1) {
	    die "Error running '$command': $errval";
	} elsif ($retval != 0) {
	    chomp($result);
	    die ($result || "Unknown error");
	}
    }

    return;
}

1;
