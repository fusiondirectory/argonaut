#######################################################################
#
# Argonaut::ClientDaemon -- Action to done on clients
#
# Copyright (C) 2011 FusionDirectory project <contact@fusiondirectory.org>
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
use Data::Dumper;

use Argonaut::Common qw(:ldap);
use Argonaut::Ldap2zone qw(argonaut_ldap2zone);

my $configfile = "/etc/argonaut/argonaut.conf";

my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

=pod
=item readConfig
Read from the config file argonaut.conf all the informations
No parameters needed
=cut
sub getServiceName {
    my ($nameFD) = @_;

    my $client_ip              =   $config->val( client => "client_ip"             ,"");
    my $ldap_configfile        =   $config->val( ldap => "config"                  ,"/etc/ldap/ldap.conf");
    my $ldap_dn                =   $config->val( ldap => "dn"                      ,"");
    my $ldap_password          =   $config->val( ldap => "password"                ,"");

    my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);

    if ($ldapinfos->{'ERROR'} > 0) {
        die $ldapinfos->{'ERRORMSG'}."\n";
    }

    my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
              base   => $ldapinfos->{'BASE'},
              filter => "(&(objectClass=argonautClient)(ipHostNumber=$client_ip))",
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

=item trigger_action_halt
shutdown the computer
=cut

sub trigger_action_halt : Public {
  my ($s, $args) = @_;
    system("sleep 5 && halt &");
    return "shuting down";
}

=item trigger_action_reboot
reboot the computer
=cut

sub trigger_action_reboot : Public {
  my ($s, $args) = @_;
    system("sleep 5 && reboot &");
    return "rebooting";
}

=item ldap2zone
launch ldap2zone on the computer and store the result in the right place
=cut

sub ldap2zone : Public {
  my ($s, $args) = @_;
  my ($zone) = @{$args};
  argonaut_ldap2zone($zone);
  return "ldap2zone done";
}

=item manage_service
execute an action on a service
=cut

sub manage_service : Public {
  my ($s, $args) = @_;
    my ($service,$action) = @{$args};
    my $folder = getServiceName("folder");
    my $exec = getServiceName($service);
    system ("$folder/$exec $action\n");
    return ("done : $action $exec");
}

=item echo
return the parameters passed to it
=cut

sub echo : Public {
  my ($s, $args) = @_;
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
