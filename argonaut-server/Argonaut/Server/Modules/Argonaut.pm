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
  my ($obj, $mac) = @_;
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
  my ($obj, $heap,$target,$action,$taskid,$params) = @_;

  my @fai_actions = ["System.reinstall", "System.update", "System.wake", "System.reboot"];
  if(grep {$_ eq $action} @fai_actions) {
    my $substatus = $obj->handler_fai($target,$action,$params);
    if(defined $taskid) {
      $heap->{tasks}->{$taskid}->{substatus} = $substatus;
    }
    return 0;
  } elsif ($action eq 'ping') {
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

=pod
item handler_fai
Put the right boot mode in the ldap and send the right thing to the client.
Parameters : the targetted mac address, the action received, the args received for it (args are currently unused).
=cut
sub handler_fai {
  my($obj, $target,$action,$args) = @_;
  my $fai_state = {
    "System.reinstall"  => "install",
    "System.update"     => "softupdate",
    "System.reboot"     => "localboot",
    "System.wake"       => "localboot"
  };

  my $need_reboot = ($action ne "System.wake");

  my $ip = $obj->flag($target,$fai_state->{$action});

  eval { # try
    if($need_reboot) {
      my $res = launch($target,"System.reboot");
      return "rebooting";
    } else {
      main::wakeOnLan($target);
      return "wake on lan";
    }
  };
  if ($@) { # catch
    $main::log->notice("Got $@ while trying to reboot, trying wake on lan");
    main::wakeOnLan($target);
    return "wake on lan";
  };
}

=item

=cut
sub flag {
  my ($obj, $target,$fai_state) = @_;
  my ($ldap,$ldap_base) = bindLdap();

  my $mesg = $ldap->search( # perform a search
            base   => $ldap_base,
            filter => "macAddress=$target"
                        # ,attrs => [ 'ipHostNumber' ]
            );

  $mesg->code && die "Error while searching entry for target address '$target' :".$mesg->error;

  if(scalar($mesg->entries)>1) {
    $main::log->error("Multiple entries were found for the Mac address $target!");
    die "Multiple entries were found for the Mac address $target!";
  } elsif(scalar($mesg->entries)<1) {
    $main::log->error("No entry were found for the Mac address $target!");
    die "No entry were found for the Mac address $target!";
  }

  my $dn = ($mesg->entries)[0];
  my $ip = ($mesg->entries)[0]->get_value("ipHostNumber");

  $mesg = $ldap->modify(
            $dn,
            replace => {
              "FAIstate" => $fai_state
              }
            );

  $mesg->code && die "Error while setting FAIstate for target address '$target' :".$mesg->error;

  $mesg = $ldap->unbind;   # take down session

  return $ip;
}

1;

__END__
