#######################################################################
#
# Argonaut::ClientDaemon -- Action to be done on clients
#
# Copyright (C) 2011-2013 FusionDirectory project <contact@fusiondirectory.org>
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
#######################################################################

package Argonaut::ClientDaemon;

use strict;
use warnings;

use 5.008;

use base qw(JSON::RPC::Procedure); # requires Perl 5.6 or later

=item echo
return the parameters passed to it
=cut

sub echo : Public {
  my ($s, $args) = @_;
  $main::log->notice("echo method called with args $args");
  return $args;
}

package
    Argonaut::ClientDaemon::system;


=item describe
should be the answer of the system.describe standard JSONRPC call. It seems broken.
=cut
sub describe {
  return {
    sdversion => "1.0",
    name      => 'Argonaut::ClientDaemon',
  };
}

1;

__END__
