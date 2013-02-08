#######################################################################
#
# Argonaut::Server::Modules::OPSI -- OPSI client module
#
# Copyright (C) 2012 FusionDirectory project <contact@fusiondirectory.org>
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

package Argonaut::Server::Modules::OPSI;

use strict;
use warnings;

use 5.008;

use Argonaut::Common qw(:ldap :file);

sub get_opsi_settings {
  my $settings = argonaut_get_generic_settings(
    'opsiClient',
    {
      'server'      => "fdOpsiServerDn",
      'cn'          => 'cn',
    },
    @_
  );
  my $cn = $settings->{'cn'};
  $cn =~ s/\.$//;

  my $ldapinfos = argonaut_ldap_init ($main::ldap_configfile, 0, $main::ldap_dn, 0, $main::ldap_password);

  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my ($ldap,$ldap_base) = ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'});

  my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
    base    => $settings->{'server'},
    scope   => 'base',
    filter  => "(objectClass=opsiServer)",
    attrs   => ['fdOpsiServerURI', 'fdOpsiServerUser', 'fdOpsiServerPassword']
  );
  $settings->{'server-uri'} = ($mesg->entries)[0]->get_value("fdOpsiServerURI");
  $settings->{'server-usr'} = ($mesg->entries)[0]->get_value("fdOpsiServerUser");
  $settings->{'server-pwd'} = ($mesg->entries)[0]->get_value("fdOpsiServerPassword");
  $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
    base    => $ldapinfos->{'BASE'},
    filter  => "(&(relativeDomainName=$cn)(aRecord=".$settings->{'ip'}."))",
    attrs   => ['zoneName']
  );
  my $zoneName = ($mesg->entries)[0]->get_value("zoneName");
  $zoneName =~ s/\.$//;
  $settings->{'fqdn'} = $cn.'.'.$zoneName;
  return $settings;
}

sub handle_client {
  my ($obj, $mac,$action) = @_;

  if ($action =~ m/^Deployment.*/) {
    return 0;
  }

  my $ip = main::getIpFromMac($mac);

  eval { #try
    get_opsi_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);
  };
  if ($@) { #catch
    return 0;
  };

  return 1;
}

=pod
=item do_action
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub do_action {
  my ($obj, $kernel,$heap,$session,$target,$action,$taskid,$params) = @_;

  if ($action eq 'ping') {
    my $res = $obj->launch($target,'hostControl_reachable','1000');
    return $res;
  } elsif ($action eq 'System.halt') {
    return $obj->launch($target,'hostControl_shutdown',$params);
  } elsif ($action eq 'System.reboot') {
    return $obj->launch($target,'hostControl_reboot',$params);
  } else {
    return $obj->launch($target,$action,$params);
  }
}

=pod
=item launch
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub launch { # if ip pings, send the request
  my ($obj, $target,$action,$params) = @_;

  my $ip = main::getIpFromMac($target);

  $main::log->info("sending action $action to $ip");

  my $settings = get_opsi_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);
  my $client_port = $settings->{'port'};

  my $client = new JSON::RPC::Client;
  $client->version('1.0');
  $client->ua->credentials($settings->{'server-uri'}, "OPSI Service", $settings->{'server-usr'}, $settings->{'server-pwd'});

  my $callobj = {
    method  => $action,
    params  => [$settings->{'fqdn'}, $params],
  };

  my $res = $client->call($settings->{'server-uri'}, $callobj);

  if($res) {
    if ($res->is_error) {
      $main::log->error("Error : ".$res->error_message);
      die "Error : ", $res->error_message."\n";
    }
    else {
      $main::log->info("Result : ".$res->result);
      return $res->result;
    }
  }
  else {
    $main::log->info("Status : ".$client->status_line);
    die "Status : ".$client->status_line."\n";
  }
}

1;

__END__
