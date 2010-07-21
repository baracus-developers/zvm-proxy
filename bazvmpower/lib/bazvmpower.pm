package bazvmpower;
use Dancer ':syntax';
use VmcpWrapper;

my @actions = ( "on", "off", "cycle", "status" );

our $VERSION = '0.1';

get '/' => sub {
    template 'index';
};

get '/power/:guest/:action' => sub {
    my $guest = params->{guest};
    my $action = params->{action};

    error "Unknown action!\n" unless (grep(/$action/,@actions));

    debug "Guest: '" . params->{guest} .
	"', Action: '" . params->{action} . "'\n";

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
