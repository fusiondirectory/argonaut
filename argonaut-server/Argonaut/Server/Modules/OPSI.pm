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
  'ping'                    => 'hostControl_reachable',
  'System.halt'             => 'hostControl_shutdown',
  'System.reboot'           => 'hostControl_reboot',
  'Deployment.reboot'       => 'hostControl_reboot',
  'Deployment.reinstall'    => \&reinstall,
  'OPSI.update_or_insert'   => \&update_or_insert,
  'OPSI.delete'             => 'host_delete',
  'OPSI.host_getObjects'    => 'host_getObjects',
  'OPSI.get_netboots'       => 'product_getObjects',
  'OPSI.get_localboots'     => 'product_getObjects',
};

my $settings;

sub new
{
  my ($class) = @_;
  my $self = {};
  bless( $self, $class );
  return $self;
}

sub needs_host_param
{
  my ($self, $action) = @_;
  #Right now update_or_insert and host_getObjects are the only actions
  # that does not require the host as first parameter
  return 0 if ($action eq 'host_getObjects');
  return 0 if ($action eq 'product_getObjects');
  return 1;
}

sub get_opsi_settings {
  my $settings;
  eval { #try
    $settings = argonaut_get_generic_settings(
      'opsiClient',
      {
        'server-dn'   => "fdOpsiServerDn",
        'profile-dn'  => "fdOpsiProfileDn",
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
    $main::log->notice("[OPSI] Client with OPSI activated but LDAP ERROR while searching server : ".$ldapinfos->{'ERRORMSG'});
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  if (not defined $settings->{'server-uri'}) {
    my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
      base    => $settings->{'server-dn'},
      scope   => 'base',
      filter  => "(objectClass=opsiServer)",
      attrs   => ['fdOpsiServerURI', 'fdOpsiServerUser', 'fdOpsiServerPassword']
    );
    if (not defined ($mesg->entries)[0]->get_value("fdOpsiServerURI")) {
      $main::log->notice("[OPSI] Client with OPSI activated but server ".$settings->{'server-dn'}." not found");
    }
    $settings->{'server-uri'} = ($mesg->entries)[0]->get_value("fdOpsiServerURI");
    $settings->{'server-usr'} = ($mesg->entries)[0]->get_value("fdOpsiServerUser");
    $settings->{'server-pwd'} = ($mesg->entries)[0]->get_value("fdOpsiServerPassword");
  }

  my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
    base    => $ldapinfos->{'BASE'},
    filter  => "(&(relativeDomainName=$cn)(aRecord=".$settings->{'ip'}."))",
    attrs   => ['zoneName']
  );
  if (($mesg->entries)[0]->get_value("zoneName")) {
    my $zoneName = ($mesg->entries)[0]->get_value("zoneName");
    $zoneName =~ s/\.$//;
    $settings->{'fqdn'} = $cn.'.'.$zoneName;
  } else {
    $main::log->notice("[OPSI] Client with OPSI activated but no DNS name");
    die "Client with OPSI activated but no DNS name";
  }

  return $settings;
}

sub handle_client {
  my ($self, $mac,$action) = @_;

  if (not defined $actions->{$action}) {
    return 0;
  }

  my $ip = main::getIpFromMac($mac);

  eval { #try
    my $settings = get_opsi_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);
    %$self = %$settings;
  };
  if ($@) { #catch
    $main::log->debug("[OPSI] Can't handle client : $@");
    return 0;
  };

  return 1;
}

sub update_task {
  my ($self, $kernel,$heap,$session,$taskid) = @_;
  if ($heap->{tasks}->{$taskid}->{status} ne 'processing') {
    return;
  }
  if ($heap->{tasks}->{$taskid}->{action} eq 'Deployment.reinstall') {
    my $attrs = [
      'actionResult',
      'actionRequest',
      'actionProgress',
      'installationStatus',
    ];
    $heap->{tasks}->{$taskid}->{progress} = 0;
    $heap->{tasks}->{$taskid}->{substatus} = "";
    if (defined $self->{'netboot'}) {
      my $filter = {
        "productId"     => $self->{'netboot'},
        "clientId"      => $self->{'fqdn'},
        "productType"   => "NetbootProduct",
      };
      my $results = $self->launch('productOnClient_getObjects',[$attrs, $filter]);
      my $res = shift @$results;
      if ($res->{'actionRequest'} eq 'setup') {
        $heap->{tasks}->{$taskid}->{substatus} = $res->{'actionProgress'};
        $heap->{tasks}->{$taskid}->{progress} = 10;
        return;
      } elsif ($res->{'installationStatus'} eq 'installed') {
        $heap->{tasks}->{$taskid}->{substatus} = 'netboot installed';
        $heap->{tasks}->{$taskid}->{progress} = 50;
      } elsif ($res->{'actionResult'} eq 'failed') {
        $heap->{tasks}->{$taskid}->{status} = "error";
        $heap->{tasks}->{$taskid}->{error} = $res->{'actionProgress'};
      }
    }
    my $nblocals = 0;
    my $nbinstalled = 0;
    my $status = "";
    if (defined $self->{'localboots'}) {
      foreach my $localboot (@{$self->{'localboots'}}) {
        $nblocals++;
        my $filter = {
          "productId"     => $localboot,
          "clientId"      => $self->{'fqdn'},
          "productType"   => "LocalbootProduct",
        };
        my $results = $self->launch('productOnClient_getObjects',[$attrs, $filter]);
        my $res = shift @$results;
        if ($res->{'actionRequest'} eq 'setup') {
          if ($res->{'actionProgress'} ne "") {
            $status = $localboot.": ".$res->{'actionProgress'};
          }
        } elsif ($res->{'installationStatus'} eq 'installed') {
          $nbinstalled++;
        } elsif ($res->{'actionResult'} eq 'failed') {
          $heap->{tasks}->{$taskid}->{status} = "error";
          $heap->{tasks}->{$taskid}->{error} = $res->{'actionProgress'};
        }
      }
    }
    if ($nblocals eq 0) {
      $heap->{tasks}->{$taskid}->{progress} = 100;
    } else {
      $heap->{tasks}->{$taskid}->{progress} += (100 - $heap->{tasks}->{$taskid}->{progress})*$nbinstalled/$nblocals;
      if ($status ne "") {
        $heap->{tasks}->{$taskid}->{substatus} = $status;
      }
    }
  }
}

sub update_or_insert {
  my ($self, $action,$params) = @_;

  my $res;

  my $infos = {
    "id"              => $self->{'fqdn'},
    "description"     => $self->{'description'},
    "hardwareAddress" => $self->{'mac'},
    "ipAddress"       => $self->{'ip'},
    "type"            => "OpsiClient",
  };
  my $opsiaction = 'host_updateObject';
  my $tmpres = $self->launch('host_getObjects',[['id'],{'id' => $self->{'fqdn'}}]);
  if (scalar(@$tmpres) < 1) {
    $opsiaction = 'host_insertObject';
    $infos->{"notes"} = "Created by FusionDirectory";
  }
  $res = $self->launch($opsiaction,[$infos]);
  if (defined $self->{'depot'}) {
    $res = $self->launch('configState_create',["clientconfig.depot.id", $self->{'fqdn'}, $self->{'depot'}]);
  }
  return $res;
}

sub reinstall {
  my ($self, $action,$params) = @_;
  my $res;

  #1 - fetch the host profile
  my $ldapinfos = argonaut_ldap_init ($main::ldap_configfile, 0, $main::ldap_dn, 0, $main::ldap_password);

  if ($ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
    base    => $self->{'profile-dn'},
    scope   => 'base',
    filter  => "(objectClass=opsiProfile)",
    attrs   => ['fdOpsiNetbootProduct', 'fdOpsiLocalbootProduct']
  );
  $self->{'netboot'}    = ($mesg->entries)[0]->get_value("fdOpsiNetbootProduct");
  $self->{'localboots'} = ($mesg->entries)[0]->get_value("fdOpsiLocalbootProduct", asref => 1);
  #2 - set netboot as the profile specifies
  if (defined $self->{'netboot'}) {
    my $infos = {
      "productId"     => $self->{'netboot'},
      "clientId"      => $self->{'fqdn'},
      "actionRequest" => "setup",
      "type"          => "ProductOnClient",
      "productType"   => "NetbootProduct",
    };
    $res = $self->launch('productOnClient_updateObject',[$infos]);
  }
  #3 - set localboot as the profile specifies (maybe remove the old ones that are not in the profile)
  if (defined $self->{'localboots'}) {
    my $infos = [];
    foreach my $localboot (@{$self->{'localboots'}}) {
      push @$infos, {
        "productId"     => $localboot,
        "clientId"      => $self->{'fqdn'},
        "actionRequest" => "setup",
        "type"          => "ProductOnClient",
        "productType"   => "LocalbootProduct"
      };
    }
    $res = $self->launch('productOnClient_updateObjects',[$infos]);
  }
  #4 - reboot the host or fire the event
  if (defined $self->{'netboot'}) {
    $res = $self->launch('hostControl_reboot',[$self->{'fqdn'}]);
  } else {
    $res = $self->launch('hostControl_fireEvent',['on_demand', $self->{'fqdn'}]);
  }

  return $res;
}

=pod
=item do_action
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub do_action {
  my ($self, $kernel,$heap,$session,$target,$action,$taskid,$params) = @_;

  if(defined $taskid) {
    $heap->{tasks}->{$taskid}->{handler} = $self;
  }

  my $ip = main::getIpFromMac($target);

  #~ %$self = get_opsi_settings($main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip);

  my $res;

  if ($action eq 'OPSI.get_netboots') {
    if (scalar @$params < 1) {
      $params->[0] = [];
    }
    if (scalar @$params < 2) {
      $params->[1] = {'type' => 'NetbootProduct'};
    }
  } elsif ($action eq 'OPSI.get_localboots') {
    if (scalar @$params < 1) {
      $params->[0] = [];
    }
    if (scalar @$params < 2) {
      $params->[1] = {'type' => 'LocalbootProduct'};
    }
  }
  if (ref $actions->{$action} eq ref "") {
    if ($action eq 'ping') {
      $params = ['1000'];
    }
    my $hostParam = $self->needs_host_param($actions->{$action});
    if ($hostParam) {
      unshift @$params, $self->{'fqdn'};
    }
    $main::log->info("[OPSI] sending action ".$actions->{$action}." to ".$self->{'fqdn'});
    $res = $self->launch($actions->{$action},$params);
    if ($hostParam) {
      if ((ref $res eq ref {}) && defined $res->{$self->{'fqdn'}}) {
        my $result = $res->{$self->{'fqdn'}};
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
    my $sub = $actions->{$action};
    $res = $self->$sub($action, $params);
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
  my ($self, $action,$params) = @_;
  if (not defined $params) {
    $params = [];
  }

  my $client = new JSON::RPC::Client;
  $client->version('1.0');
  my $host = $self->{'server-uri'};
  $host =~ s|^http(s?)://||;
  $host =~ s|/.*$||;
  $client->ua->credentials($host, "OPSI Service", $self->{'server-usr'}, $self->{'server-pwd'});

  my $callobj = {
    method  => $action,
    params  => [@$params],
  };

  $main::log->debug("[OPSI] Call : ".Dumper($callobj));
  my $res = $client->call($self->{'server-uri'}, $callobj);

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
