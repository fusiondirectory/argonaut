package Argonaut::Debconf::PXE;

=head1 DESCRIPTION

Abstraction of the PXE-related components.

Initialize it by calling e.g. $p= $system->PXE, and
display it as config file via $p->as_pxelinux_cfg or
(and alias) $p->as_config.

See also $system->Config for a generic implementation.

=cut

use warnings;
use strict;

use Argonaut::Debconf::Common   qw/:public/;
use base qw/Argonaut::Debconf::Config/;

sub new {
	(shift)->SUPER::new( filter => 'flags=append', @_)
}

sub as_config { (shift)->as_pxelinux_cfg( @_)}

1

__END__
=head1 REFERENCES

=head1 AUTHORS

SPINLOCK - Advanced GNU/Linux networks in commercial and education sectors.

Copyright 2011, Davor Ocelic <docelic@spinlocksolutions.com>

Copyright 2011, SPINLOCK Solutions,
  http://www.spinlocksolutions.com/,
  http://techpubs.spinlocksolutions.com/

=head1 LICENSE

GNU GPL v3 or later. http://www.gnu.org/licenses/gpl.html

=cut
