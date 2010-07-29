package Baracus::PidCreator;

use 5.010000;
use strict;
use warnings;

require Exporter;

use Fcntl;	# for sysopen
use File::Basename;

our @ISA = qw(Exporter);

our @EXPORT_OK = ();

our @EXPORT = ();

our $VERSION = '0.01';

# Preloaded methods go here.

BEGIN {
    my $daemon_name = $ENV{'BARACUS_PIDCREATOR_NAME'} || basename($0, '.pl');
    my $daemon_pidfile = "/var/run/" . $daemon_name . ".pid";

    sysopen(PIDFILE, $daemon_pidfile, O_WRONLY | O_CREAT | O_EXCL, 0600)
	or die "Can not create pid file ('$daemon_pidfile'): $!\n";
    print PIDFILE $$;
    close(PIDFILE);
}

1;
__END__
# Below is stub documentation for your module. You'd better edit it!

=head1 NAME

Baracus::PidCreator - Plackup Perl module for creation of a pid file

=head1 SYNOPSIS

  plackup ... -M Baracus::PidCreator ...

=head1 DESCRIPTION

This is a Perl module that creates a pid file when it is used. Plackup supports
loading it just before loading application code.

=head2 EXPORT

None by default.



=head1 SEE ALSO

plackup(1)

=head1 AUTHOR

Jan Blunck, E<lt>jblunck@novell.comE<gt>

=head1 COPYRIGHT AND LICENSE

Copyright (C) 2010 by Jan Blunck

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself, either Perl version 5.10.0 or,
at your option, any later version of Perl 5 you may have available.


=cut
