package Argonaut::Debconf::Preseed;

=head1 DESCRIPTION

Abstraction of the preseed.cfg file for a host.

Initialize it by calling e.g. $p= $system->Preseed, and
display it as config file via $p->as_preseed_cfg or
(an alias) $p->as_config.

See also $system->Config for a generic implementation.

=cut

use warnings;
use strict;

use Argonaut::Debconf::Common   qw/:public/;
use Argonaut::Debconf::Question qw/:public/;
use Argonaut::Debconf::Template qw/:public/;
use base qw/Argonaut::Debconf::Config/;

sub new {
  (shift)->SUPER::new( filter => 'flags=preseed', @_)
}

sub as_config { (shift)->as_preseed_cfg( @_)}

1

__END__
=head1 REFERENCES

=head1 AUTHORS

SPINLOCK - Advanced GNU/Linux networks in commercial and education sectors.

Copyright (C) 2011, Davor Ocelic <docelic@spinlocksolutions.com>
Copyright (C) 2011-2013 FusionDirectory project

Copyright 2011, SPINLOCK Solutions,
  http://www.spinlocksolutions.com/,
  http://techpubs.spinlocksolutions.com/

=head1 LICENSE

GNU GPL v3 or later. http://www.gnu.org/licenses/gpl.html

=cut
