package bazvmpower;
use Dancer ':syntax';
use VmcpWrapper;

my @actions = ( "on", "off", "cycle", "status" );

our $VERSION = '0.1';
our $baaddress = eval {
    use Socket;

    # Our default configuration variables
    our $baurl = "http://localhost/ba/";
    # Read in (perl style) configuration file
    my $confpath = "/etc/bazvmproxy.conf";
    if (-s $confpath) {
	debug "Using configuration file " . $confpath;
	do $confpath;
    }

    my $address;
    if ($baurl =~ m/^(\w+\:\/\/)?([a-zA-Z0-9\-\.]+)(\/.*)?$/) {
	$address = inet_ntoa(inet_aton($2)) or die "Can't resolve $2: $!\n";
    }
    $address;
};
debug "Using Baracus server at $baaddress\n";

get '/' => sub {
    template 'index';
};

get '/power/:guest/:action' => sub {
    my $guest = params->{guest};
    my $action = params->{action};

    error "Unknown action!\n" unless (grep(/$action/,@actions));

    debug "Guest: '" . params->{guest} .
	"', Action: '" . params->{action} . "'\n";

    debug "Host: '" . request->{host} . "'\n";
    debug "Remote: '" . request->remote_address . "'\n";

    my %reqenv = %{request->env};
    while (my($key, $value) = each %reqenv) {
	debug "$key: " . (defined $value ? $value : "" ) . "\n";
    }

    if (request->remote_address ne $baaddress) {
	error("Not authorized");
	return { error => "Not authorized" };
    }

    eval {
	my $result = power($action, $guest);
	return { guest => params->{guest}, status => $result };
	1;
    } or do {
	my $err = $@ || "Unknown error";
	error($err);
	return { error => $@ || "Unknown error" };
    };
};

true;
