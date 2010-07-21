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

# "Usage: $0 <operation> <guestname>\n";
# "    e.g. operation = 'status'\n";
# "         guestname = 'LINUX101'\n";
sub power
{
    local($operation, $hostname) = @_;
    local($command, $result);

    die "Invalid argument: '" . join(" ", @_) . "'"
	unless ((scalar(@_) == 2) && grep(/$operation/,keys(%operations)));

    $command = sprintf( $operations{ $operation }, $hostname );

    if ( $operation eq "status") {
	$command .= " 2>&1 1>/dev/null";
	$result = `$command`;
	if ($? == -1) {
	    die "Error running '$command': $!";
	} elsif ( $? == 0 ) {
	    return "Online";
	} elsif ( $? == 256 ) {
	    $result =~ m/^Error:.*: #(\d+)$/;
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
	$result = `$command`;
	if ($? == -1) {
	    die "Error running '$command': $!";
	} elsif ($? != 0) {
	    chomp($result);
	    die ($result || "Unknown error");
	}
    }

    return;
}

1;
