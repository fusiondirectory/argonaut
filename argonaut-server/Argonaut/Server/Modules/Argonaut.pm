#######################################################################
#
# Argonaut::Server::Modules::Argonaut -- Argonaut client module
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

package Argonaut::Server::Modules::Argonaut;

use strict;
use warnings;

use 5.008;

use Argonaut::Common qw(:ldap :file);

sub handle_client {
  my ($obj, $mac,$action) = @_;

  if ($action =~ m/^Deployment.*/) {
    return 0;
  }

  my $ip = main::getIpFromMac($mac);

  eval { #try
    argonaut_get_client_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);
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
    my $ok = 'OK';
    my $res = $obj->launch($target,'echo',$ok);
    return ($res eq $ok);
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

  if ($action =~ m/^[^.]+\.[^.]+$/) {
    $action = 'Argonaut.ClientDaemon.Modules.'.$action;
  }

  my $ip = main::getIpFromMac($target);
  # this line is only needed when debugging stuff on localhost
  #$ip = "localhost";

  $main::log->info("sending action $action to $ip");

  my $settings = argonaut_get_client_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);
  my $client_port = $settings->{'port'};

  my $client = new JSON::RPC::Client;
  $client->version('1.0');
  if ($main::protocol eq 'https') {
    if ($client->ua->can('ssl_opts')) {
      $client->ua->ssl_opts(verify_hostname => 1,SSL_ca_file => "dummy_ca.crt");
    }
    $client->ua->credentials($ip.":".$client_port, "JSONRPCRealm", "foo", "secret");
  }

  my $callobj = {
    method  => $action,
    params  => [$params],
  };

  my $res = $client->call($main::protocol."://".$ip.":".$client_port, $callobj);

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
