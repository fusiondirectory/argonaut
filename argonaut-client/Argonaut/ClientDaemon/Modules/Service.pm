#######################################################################
#
# Argonaut::ClientDaemon::Modules::Service -- Service management
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

package Argonaut::ClientDaemon::Modules::Service;

use strict;
use warnings;

use 5.008;

use base qw(JSON::RPC::Procedure); # requires Perl 5.6 or later

use Argonaut::Libraries::Common qw(:ldap);

=item getServiceName
Returns the local name of a service
=cut
sub getServiceName : Private {
    my ($nameFD) = @_;

    my $ldapinfos = argonaut_ldap_init ($main::ldap_configfile, 0, $main::ldap_dn, 0, $main::ldap_password);

    if ($ldapinfos->{'ERROR'} > 0) {
        die $ldapinfos->{'ERRORMSG'}."\n";
    }

    my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
              base   => $ldapinfos->{'BASE'},
              filter => "(&(objectClass=argonautClient)(ipHostNumber=".$main::client_settings->{'ip'}."))",
              attrs => [ 'argonautServiceName' ]
            );

    if (scalar($mesg->entries)==1) {
        foreach my $service (($mesg->entries)[0]->get_value("argonautServiceName")) {
            my ($name,$value) = split(':',$service);
            return $value if ($name eq $nameFD);
        }
    }
    die "Service not found";
}

=item manage
execute an action on a service
return a string that begins with "done" if it worked.
=cut
sub manage : Public {
  my ($s, $args) = @_;
  my ($service,$action) = @{$args};
  my $folder  = getServiceName("folder");
  my $exec    = getServiceName($service);
  $main::log->notice("manage service called: $service ($folder/$exec) $action");
  system ("$folder/$exec $action\n") == 0 or die "$folder/$exec $action returned error $?";;
  return "done : $action $exec";
}

=item is_running
returns "yes" or "no" wether if a service is running or not
=cut
sub is_running : Public {
  my ($s, $args) = @_;
  my ($service) = @{$args};
  my $folder  = getServiceName("folder");
  my $exec    = getServiceName($service);
  $main::log->notice("is_running service called: $service ($folder/$exec) status");
  my $lsb_code = system ("$folder/$exec status\n");
  if ($lsb_code == 0) {
    return "yes";
  } else {
    return "no";
  }
}

1;

__END__
