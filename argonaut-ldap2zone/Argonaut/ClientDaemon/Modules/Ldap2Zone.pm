#######################################################################
#
# Argonaut::ClientDaemon::Modules::Ldap2Zone -- Ldap2Zone remote call
#
# Copyright (C) 2012-2016 FusionDirectory project
#
# Author: Côme BERNIGAUD
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
#######################################################################

package Argonaut::ClientDaemon::Modules::Ldap2Zone;

use strict;
use warnings;

use 5.008;

use Argonaut::Libraries::Common qw(:config);
use Argonaut::Libraries::Ldap2zone qw(argonaut_ldap2zone);

my $base;
BEGIN {
  $base = (USE_LEGACY_JSON_RPC ? "JSON::RPC::Legacy::Procedure" : "JSON::RPC::Procedure");
}
use base $base;

=item start
start ldap2zone on the computer and store the result in the right place
=cut
sub start : Public {
  my ($s, $args) = @_;
  my ($zone) = @{$args};
  $main::log->notice("ldap2zone called");
  argonaut_ldap2zone($zone);
  return "ldap2zone done";
}

1;

__END__
