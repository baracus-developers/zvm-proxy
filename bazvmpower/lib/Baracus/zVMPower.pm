package Baracus::zVMPower;
use Dancer ':syntax';
use Baracus::VmcpWrapper;

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

get '/power/:action' => sub {
    my $guest = params->{node};
    my $action = params->{action};

    return send_error("Unknown action!\n", 400)
	unless (grep(/$action/,@actions));

    return send_error("Node undefined!\n", 400)
	unless (defined(params->{node}));

    debug "Guest: '" . params->{node} .
	"', Action: '" . params->{action} . "'\n";

    debug "Host: '" . request->{host} . "'\n";
    debug "Remote: '" . request->remote_address . "'\n";

    my %reqenv = %{request->env};
    while (my($key, $value) = each %reqenv) {
	debug "$key: " . (defined $value ? $value : "" ) . "\n";
    }

    if (request->remote_address ne $baaddress &&
	request->remote_address ne "127.0.0.1") {
	error("Forbidden: IP: '" . request->remote_address .
	      "', REQUEST_URI: '" . request->request_uri .
	      "', HTTP_USER_AGENT: '" . request->user_agent . "'\n");
	return send_error("Forbidden", 403);
    }

    eval {
	my $result = power($action, $guest);
	return { guest => params->{node}, status => $result };
	1;
    } or do {
	my $err = $@ || "Unknown error: ($?) $!";
	error($err);
	return send_error($err, 500);
    };
};

true;
