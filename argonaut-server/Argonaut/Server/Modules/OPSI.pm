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
use Data::Dumper;

use 5.008;

use Argonaut::Common qw(:ldap :file);

my $actions = {
  'ping'                  => 'hostControl_reachable',
  'System.halt'           => 'hostControl_shutdown',
  'System.reboot'         => 'hostControl_reboot',
  'Deployment.reboot'     => 'hostControl_reboot',
  'OPSI.update_or_insert' => 'update_or_insert',
  'OPSI.host_getObjects'  => 'host_getObjects',
};

sub get_opsi_settings {
  my $settings;
  eval { #try
    $settings = argonaut_get_generic_settings(
      'opsiClient',
      {
        'server-dn'   => "fdOpsiServerDn",
        'description' => "description",
        'cn'          => 'cn',
      },
      @_
    );
  };
  if ($@) { #catch
    my $error = $@;
    eval {
      $settings = argonaut_get_generic_settings(
        'opsiServer',
        {
          'server-uri'      => "fdOpsiServerURI",
          'server-usr'      => "fdOpsiServerUser",
          'server-pwd'      => "fdOpsiServerPassword",
          'description'     => "description",
          'cn'              => 'cn',
        },
        @_
      );
    };
    if ($@) {
      die $error;
    };
  };
  my $cn = $settings->{'cn'};
  $cn =~ s/\$$//;

  my $ldapinfos = argonaut_ldap_init ($main::ldap_configfile, 0, $main::ldap_dn, 0, $main::ldap_password);

  if ($ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  if (not defined $settings->{'server-uri'}) {
    my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
      base    => $settings->{'server-dn'},
      scope   => 'base',
      filter  => "(objectClass=opsiServer)",
      attrs   => ['fdOpsiServerURI', 'fdOpsiServerUser', 'fdOpsiServerPassword']
    );
    $settings->{'server-uri'} = ($mesg->entries)[0]->get_value("fdOpsiServerURI");
    $settings->{'server-usr'} = ($mesg->entries)[0]->get_value("fdOpsiServerUser");
    $settings->{'server-pwd'} = ($mesg->entries)[0]->get_value("fdOpsiServerPassword");
  }

  my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
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

  if (not defined $actions->{$action}) {
    return 0;
  }

  my $ip = main::getIpFromMac($mac);

  eval { #try
    get_opsi_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);
  };
  if ($@) { #catch
    $main::log->debug("[OPSI] Can't handle client : $@");
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

  my $ip = main::getIpFromMac($target);

  my $settings = get_opsi_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);

  my $res;

  if ($action eq 'OPSI.update_or_insert') {
    my $infos = {
      "id"              => $settings->{'fqdn'},
      "description"     => $settings->{'description'},
      "hardwareAddress" => $settings->{'mac'},
      "ipAddress"       => $settings->{'ip'},
      "type"            => "OpsiClient",
    };
    my $opsiaction = 'host_updateObject';
    my $tmpres = $obj->launch($settings,'host_getObjects',[['id'],{'id' => $settings->{'fqdn'}}]);
    if (scalar(@$tmpres) < 1) {
      $opsiaction = 'host_insertObject';
      $infos->{"notes"} = "Created by FusionDirectory";
    }
    $res = $obj->launch($settings,$opsiaction,[$infos]);
    if (defined $settings->{'depot'}) {
      $res = $obj->launch($settings,'configState_create',["clientconfig.depot.id", $settings->{'fqdn'}, $settings->{'depot'}]);
    }
  } elsif (defined $actions->{$action}) {
    if ($action eq 'ping') {
      $params = ['1000'];
    }
    my $hostControl = (($actions->{$action} =~ m/^hostControl/) || ($action eq 'ping'));
    if ($hostControl) {
      unshift @$params, $settings->{'fqdn'};
    }
    $main::log->info("[OPSI] sending action ".$actions->{$action}." to ".$settings->{'fqdn'});
    $res = $obj->launch($settings,$actions->{$action},$params);
    if ($hostControl) {
      if ((ref $res eq ref {}) && defined $res->{$settings->{'fqdn'}}) {
        my $result = $res->{$settings->{'fqdn'}};
        if (JSON::XS::is_bool($result)) {
          $res = $result;
        } elsif (defined $result->{'error'}) {
          $main::log->error("[OPSI] Error : ".$result->{'error'});
          die "Error : ", $result->{'error'}."\n";
        } elsif (defined $result->{'result'}) {
          $res = $result->{'result'};
        } else {
          undef $res;
        }
      }
    }
  } else {
    $res = $obj->launch($settings,$action,$params);
  }

  if (not defined $res) {
    $main::log->info("[OPSI] Result is empty (no errors though)");
    return 1;
  }
  $main::log->info("[OPSI] Result : ".$res);
  return $res;
}

=pod
=item launch
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub launch { # if ip pings, send the request
  my ($obj, $settings,$action,$params) = @_;
  if (not defined $params) {
    $params = [];
  }

  my $client = new JSON::RPC::Client;
  $client->version('1.0');
  my $host = $settings->{'server-uri'};
  $host =~ s|^http(s?)://||;
  $host =~ s|/.*$||;
  $client->ua->credentials($host, "OPSI Service", $settings->{'server-usr'}, $settings->{'server-pwd'});

  my $callobj = {
    method  => $action,
    params  => [@$params],
  };

  $main::log->debug("[OPSI] Call : ".Dumper($callobj));
  my $res = $client->call($settings->{'server-uri'}, $callobj);

  if($res) {
    $main::log->debug("[OPSI] Answer : ".Dumper($res));
    if ($res->is_error) {
      $main::log->error("[OPSI] Error : ".$res->error_message->{'message'});
      die "Error : ", $res->error_message->{'message'}."\n";
    } else {
      return $res->result;
    }
  } else {
    $main::log->info("[OPSI] Status : ".$client->status_line);
    die "Status : ".$client->status_line."\n";
  }
}

1;

__END__
