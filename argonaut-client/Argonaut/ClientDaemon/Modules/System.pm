#######################################################################
#
# Argonaut::ClientDaemon::Modules::System -- System management
#
# Copyright (C) 2012-2013 FusionDirectory project <contact@fusiondirectory.org>
#
# Author: Côme BERNIGAUD
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

package Argonaut::ClientDaemon::Modules::System;

use strict;
use warnings;

use 5.008;

use Argonaut::Libraries::Common qw(:ldap :config);

my $base;
BEGIN {
  $base = (USE_LEGACY_JSON_RPC ? "JSON::RPC::Legacy::Procedure" : "JSON::RPC::Procedure");
}
use base $base;

=item halt
shutdown the computer
=cut
sub halt : Public {
  my ($s, $args) = @_;
  $main::log->notice("halt called");
  system("sleep 5 && halt &");
  return "shuting down";
}

=item reboot
reboot the computer
=cut
sub reboot : Public {
  my ($s, $args) = @_;
  $main::log->notice("reboot called, rebooting…");
  system("sleep 5 && reboot &");
  return "rebooting";
}

1;

__END__
