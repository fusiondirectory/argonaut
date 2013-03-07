package Argonaut::Debconf::Init;

=head1 DESCRIPTION

Convenience class to load all the relevant classes and
initialize the whole thing.

In your program, simply call:

  use Argonaut::Debconf::Init qw//;

Note that this will "use" the modules, but you'll
still have to use this to import shared variables:

  use Argonaut::Debconf::Common qw/:public/;

=cut

use warnings;
use strict;

use Argonaut::Debconf::Common    qw//;
use Argonaut::Debconf::System    qw//;
use Argonaut::Debconf::Question  qw//;
use Argonaut::Debconf::Template  qw//;
use Argonaut::Debconf::Key       qw//;
use Argonaut::Debconf::Tree      qw//;
use Argonaut::Debconf::Preseed   qw//;
use Argonaut::Debconf::PXE       qw//;

Argonaut::Debconf::Common->init_config; # $C

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
