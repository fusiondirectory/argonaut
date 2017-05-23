#######################################################################
#
# Argonaut::Server::Modules::OPSI -- OPSI client module
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

package Argonaut::Server::Modules::OPSI;

use strict;
use warnings;
use Data::Dumper;
use JSON;

use 5.008;

use Argonaut::Libraries::Common qw(:ldap :file :config);

my $actions = {
  'ping'                        => 'hostControl_reachable',
  'System.halt'                 => 'hostControl_shutdown',
  'System.reboot'               => 'hostControl_reboot',
  'Deployment.reboot'           => 'hostControl_reboot',
  'Deployment.reinstall'        => \&reinstall,
  'Deployment.update'           => \&update,
  'OPSI.update_or_insert'       => \&update_or_insert,
  'OPSI.delete'                 => 'host_delete',
  'OPSI.host_getObjects'        => 'host_getObjects',
  'OPSI.get_netboots'           => 'product_getObjects',
  'OPSI.get_localboots'         => 'product_getObjects',
  'OPSI.get_product_properties' => 'productProperty_getObjects',
};

my @locked_actions = (
  'ping',
  'OPSI.update_or_insert', 'OPSI.delete',
  'OPSI.host_getObjects', 'OPSI.get_netboots', 'OPSI.get_localboots',
);

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
  my ($self, $action, $params) = @_;
  #Right now update_or_insert and host_getObjects are the only actions
  # that does not require the host as first parameter
  return 0 if ($action eq 'productProperty_getObjects');
  return 0 if ($action eq 'host_getObjects');
  return 0 if ($action eq 'product_getObjects');
  return 0 if (($action eq 'host_delete') && (@$params > 0));
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
        },
        @_
      );
    };
    if ($@) {
      die $error;
    };
  };

  my ($ldap, $ldap_base) = argonaut_ldap_handle($main::config);

  if (not defined $settings->{'server-uri'}) {
    my $mesg = $ldap->search( # perform a search
      base    => $settings->{'server-dn'},
      scope   => 'base',
      filter  => "(objectClass=opsiServer)",
      attrs   => ['fdOpsiServerURI', 'fdOpsiServerUser', 'fdOpsiServerPassword']
    );
    if ($mesg->count <= 0) {
      die "[OPSI] Client with OPSI activated but server ".$settings->{'server-dn'}." not found";
    }
    $settings->{'server-uri'} = ($mesg->entries)[0]->get_value("fdOpsiServerURI");
    $settings->{'server-usr'} = ($mesg->entries)[0]->get_value("fdOpsiServerUser");
    $settings->{'server-pwd'} = ($mesg->entries)[0]->get_value("fdOpsiServerPassword");
  }

  my $host_settings = get_winstation_fqdn_settings(@_);
  @$settings{keys %$host_settings} = @$host_settings{keys %$host_settings};

  return $settings;
}

sub get_winstation_fqdn_settings {
  my $settings = argonaut_get_generic_settings(
    '*',
    {
      'cn'              => 'cn',
      'description'     => 'description',
    },
    @_,
    0
  );
  my $cn = $settings->{'cn'};
  $cn =~ s/\$$//;

  my ($ldap, $ldap_base) = argonaut_ldap_handle($main::config);

  my $mesg = $ldap->search( # perform a search
    base    => $ldap_base,
    filter  => "(&(relativeDomainName=$cn)(aRecord=".$settings->{'ip'}.")(zoneName=*))",
    attrs   => ['zoneName']
  );
  if ($mesg->count <= 0) {
    die "[OPSI] Could not find any DNS domain name for $cn";
  }
  my $zoneName = ($mesg->entries)[0]->get_value("zoneName");
  $zoneName =~ s/\.$//;
  $settings->{'fqdn'} = $cn.'.'.$zoneName;

  return $settings;
}

sub handle_client {
  my ($self, $mac,$action) = @_;

  if (not defined $actions->{$action}) {
    return 0;
  }

  my $ip = main::getIpFromMac($mac);

  eval { #try
    my $settings = get_opsi_settings($main::config,$ip);
    %$self = %$settings;
    $self->{action} = $action;
  };
  if ($@) { #catch
    if ($@ =~ /^[OPSI]/) {
      $main::log->notice($@);
    } else {
      $main::log->debug("[OPSI] Can't handle client : $@");
    }
    return 0;
  };

  return 1;
}

=item update_task
Update a task status.
Takes the task infos as parameter, return the new tasks infos.
=cut
sub update_task {
  my ($self, $task) = @_;
  if ($task->{status} ne 'processing') {
    return $task;
  }
  if (($task->{action} eq 'Deployment.reinstall') || ($task->{action} eq 'Deployment.update')) {
    my $attrs = [
      'actionResult',
      'actionRequest',
      'actionProgress',
      'installationStatus',
    ];
    $task->{progress} = 10;
    $task->{substatus} = "";
    if (defined $self->{'netboot'}) {
      my $filter = {
        "productId"     => $self->{'netboot'},
        "clientId"      => $self->{'fqdn'},
        "productType"   => "NetbootProduct",
      };
      my $results = $self->launch('productOnClient_getObjects',[$attrs, $filter]);
      my $res = shift @$results;
      if ($res->{'actionRequest'} eq 'setup') {
        $task->{substatus}  = $res->{'actionProgress'};
        $task->{progress}   = 20;
        return $task;
      } elsif ($res->{'installationStatus'} eq 'installed') {
        $task->{substatus}  = 'netboot installed';
        $task->{progress}   = 50;
      } elsif ($res->{'actionResult'} eq 'failed') {
        $task->{status} = "error";
        $task->{error}  = $res->{'actionProgress'};
        return $task;
      }
    }
    my $nblocals = 0;
    my $nbinstalled = 0;
    my $status = "";
    if (defined $self->{'localboots'}) {
      foreach my $localboot (@{$self->{'localboots'}}) {
        my ($product, $action) = split('\|',$localboot);
        $nblocals++;
        my $filter = {
          "productId"     => $product,
          "clientId"      => $self->{'fqdn'},
          "productType"   => "LocalbootProduct",
        };
        my $results = $self->launch('productOnClient_getObjects',[$attrs, $filter]);
        my $res = shift @$results;
        if ($res->{'actionRequest'} eq $action) {
          if ($res->{'actionProgress'} ne "") {
            $status = $product.": ".$res->{'actionProgress'};
          }
        } elsif ($res->{'installationStatus'} eq 'installed') {
          $nbinstalled++;
        } elsif ($res->{'actionResult'} eq 'failed') {
          $task->{status} = "error";
          $task->{error} = $res->{'actionProgress'};
          return $task;
        }
      }
    }
    if ($nblocals eq 0) {
      $task->{progress} = 100;
    } else {
      $task->{progress} += (100 - $task->{progress}) * $nbinstalled / $nblocals;
      if ($status ne "") {
        $task->{substatus} = $status;
      }
    }
  }
  return $task;
}

sub task_processed {
  my ($self, $task) = @_;
  return $task;
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

sub reinstall_or_update {
  my ($self, $reinstall,$action,$params) = @_;

  #1 - fetch the host profile
  my ($ldap, $ldap_base) = argonaut_ldap_handle($main::config);

  my $mesg = $ldap->search( # perform a search
    base    => $self->{'profile-dn'},
    scope   => 'base',
    filter  => "(objectClass=opsiProfile)",
    attrs   => ['fdOpsiNetbootProduct', 'fdOpsiSoftwareList', 'fdOpsiProductProperty']
  );
  if ($mesg->count <= 0) {
    die "[OPSI] Client with OPSI activated but profile '".$settings->{'profile-dn'}."' could not be found";
  }
  $self->{'netboot'}    = ($mesg->entries)[0]->get_value("fdOpsiNetbootProduct");
  $self->{'softlists'}  = ($mesg->entries)[0]->get_value("fdOpsiSoftwareList", asref => 1);
  $self->{'localboots'} = [];
  $self->{'properties'} = ($mesg->entries)[0]->get_value("fdOpsiProductProperty", asref => 1);
  #2 - remove existing setups and properties
  my $productOnClients = $self->launch('productOnClient_getObjects',
    [[],
    {
      "clientId"      => $self->{'fqdn'},
      "type"          => "ProductOnClient",
    }]
  );
  my $productStates = {};
  foreach my $product (@$productOnClients) {
    $productStates->{$product->{'productId'}} = $product->{'installationStatus'};
    $product->{"actionRequest"} = 'none';
  }
  $self->launch('productOnClient_updateObjects', [$productOnClients]);
  my $productPropertyStates = $self->launch('productPropertyState_getObjects',
    [[],
    {
      "objectId"      => $self->{'fqdn'},
      "type"          => "ProductPropertyState",
    }]
  );
  if (scalar(@$productPropertyStates) > 0) {
    $self->launch('productPropertyState_deleteObjects', [$productPropertyStates]);
  }
  #3 - set netboot as the profile specifies
  if (!$reinstall && defined $self->{'netboot'}) {
    # Check if netboot is correctly installed
    if ((not exists($productStates->{$self->{'netboot'}})) || ($productStates->{$self->{'netboot'}} ne 'installed')) {
      $reinstall = 1;
    }
  }
  if ($reinstall && defined $self->{'netboot'}) {
    my $infos = {
      "productId"     => $self->{'netboot'},
      "clientId"      => $self->{'fqdn'},
      "actionRequest" => "setup",
      "type"          => "ProductOnClient",
      "productType"   => "NetbootProduct",
    };
    $self->launch('productOnClient_updateObject',[$infos]);
  } else {
    #3 bis - set to uninstall product that are not in the profile
    # (all products on the client for now - step 4 will cancel uninstall on needed products)
    my $infos = [];
    foreach my $product (@$productOnClients) {
      if (($product->{"productType"} eq "LocalbootProduct") &&
          ($product->{"installationStatus"} eq "installed") &&
          ($product->{"productId"} ne 'opsi-client-agent') &&
          ($product->{"productId"} ne 'opsi-winst')) {
        push @$infos, {
          "productId"     => $product->{"productId"},
          "clientId"      => $self->{'fqdn'},
          "type"          => "ProductOnClient",
          "productType"   => "LocalbootProduct",
          "actionRequest" => "uninstall",
        };
      }
    }
    if (scalar(@$infos) > 0) {
      $self->launch('productOnClient_updateObjects',[$infos]);
    }
  }
  #4 - set localboot as the profile specifies (maybe remove the old ones that are not in the profile - see 3 bis)
  if (defined $self->{'softlists'}) {
    my $infos = [];
    foreach my $softlistdn (@{$self->{'softlists'}}) {
      my $mesg = $ldap->search( # perform a search
        base    => $softlistdn,
        scope   => 'base',
        filter  => "(|(objectClass=opsiSoftwareList)(objectClass=opsiOnDemandList))",
        attrs   => ['objectClass', 'fdOpsiLocalbootProduct', 'cn', 'fdOpsiOnDemandShowDetails']
      );
      my $ocs = ($mesg->entries)[0]->get_value("objectClass", asref => 1);
      my $localboots = ($mesg->entries)[0]->get_value("fdOpsiLocalbootProduct", asref => 1);
      if (not defined $localboots) {
        next;
      }
      if (grep {$_ eq 'opsiSoftwareList'} @$ocs) {
        foreach my $localboot (@{$localboots}) {
          my ($product, $action) = split('\|',$localboot);
          push @{$self->{'localboots'}}, $localboot;
          if ($reinstall || ($action ne 'setup') || (! defined $productStates->{$product}) || ($productStates->{$product} ne 'installed')) {
            push @$infos, {
              "productId"     => $product,
              "clientId"      => $self->{'fqdn'},
              "actionRequest" => $action,
              "type"          => "ProductOnClient",
              "productType"   => "LocalbootProduct"
            };
          } else {
            push @$infos, {
              "productId"     => $product,
              "clientId"      => $self->{'fqdn'},
              "actionRequest" => "none",
              "type"          => "ProductOnClient",
              "productType"   => "LocalbootProduct"
            };
          }
        }
      } else {
        # Handle OnDemandList
        my $groupid     = 'fd_ondemand_'.($mesg->entries)[0]->get_value('cn');
        my $showdetails = (($mesg->entries)[0]->get_value('fdOpsiOnDemandShowDetails') eq "TRUE");
        $self->launch('group_delete',[$groupid]);
        $self->launch('group_createProductGroup',[$groupid]);
        foreach my $localboot (@{$localboots}) {
          $self->launch('objectToGroup_create',['ProductGroup', $groupid, $localboot]);
        }
        $self->launch('configState_create',['software-on-demand.active', $self->{'fqdn'}, JSON::true]);
        $self->launch('configState_create',['software-on-demand.product-group-ids', $self->{'fqdn'}, [$groupid]]);
        $self->launch('configState_create',['software-on-demand.show-details', $self->{'fqdn'}, ($showdetails?JSON::true:JSON::false)]);
      }
    }
    if (scalar(@$infos) > 0) {
      $self->launch('productOnClient_updateObjects',[$infos]);
    }
  }
  #5 - set properties as the profile specifies
  if (defined $self->{'properties'}) {
    my $infos = [];
    foreach my $property (@{$self->{'properties'}}) {
      my ($product, $propid, $values) = split('\|',$property);
      push @$infos, {
        "productId"     => $product,
        "propertyId"    => $propid,
        "objectId"      => $self->{'fqdn'},
        "values"        => decode_json($values),
        "type"          => "ProductPropertyState",
      };
    }
    if (scalar(@$infos) > 0) {
      $self->launch('productPropertyState_updateObjects',[$infos]);
    }
  }
  #6 - reboot the host or fire the event
  my $res;
  if (defined $self->{'netboot'}) {
    $res = $self->launch('hostControl_reboot',[$self->{'fqdn'}]);
  } else {
    $res = $self->launch('hostControl_fireEvent',['on_demand', $self->{'fqdn'}]);
  }

  # If we did not die until here, all went well
  $self->{task}->{'substatus'}  = 'Order sent';
  $self->{task}->{'progress'}   = 10;

  return $res;
}

sub reinstall {
  my ($self, $action,$params) = @_;

  return $self->reinstall_or_update(1, $action, $params);
}

sub update {
  my ($self, $action,$params) = @_;

  return $self->reinstall_or_update(0, $action, $params);
}

=pod
=item do_action
Execute a JSON-RPC method on a client which the ip is given.
Parameters :$target,$taskid,$params
=cut
sub do_action {
  my ($self, $params) = @_;
  my $action = $self->{action};
  my $taskid = $self->{taskid};

  if ($self->{'locked'} && not (grep {$_ eq $action} @locked_actions)) {
    die 'This computer is locked';
  }

  $self->{task}->{handler} = 1;

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
  } elsif (($action eq 'OPSI.delete') && (scalar @$params > 0)) {
    my @fqdns = ();
    foreach my $host (@{$params->[0]}) {
      if (lc($host) =~ m/([0-9a-f]{2}:){5}[0-9a-f]{2}/) { # If host is a macAddress
        my $ip = main::getIpFromMac($host);
        my $host_settings = get_winstation_fqdn_settings($main::config,$ip);
        push @fqdns, $host_settings->{'fqdn'};
      } else {
        push @fqdns, $host;
      }
    }
    $params->[0] = \@fqdns;
  }
  if (ref $actions->{$action} eq ref "") {
    if ($action eq 'ping') {
      $params = ['1000'];
    }
    my $hostParam = $self->needs_host_param($actions->{$action}, $params);
    if ($hostParam) {
      unshift @$params, $self->{'fqdn'};
    }
    $main::log->info("[OPSI] sending action ".$actions->{$action}." to ".$self->{'fqdn'});
    $res = $self->launch($actions->{$action}, $params);
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
sub launch {
  my ($self, $action,$params) = @_;
  if (not defined $params) {
    $params = [];
  }

  my $client;
  if (USE_LEGACY_JSON_RPC) {
    $client = new JSON::RPC::Legacy::Client;
  } else {
    $client = new JSON::RPC::Client;
  }
  $client->version('1.0');
  my $host = $self->{'server-uri'};
  $host =~ s|^http(s?)://||;
  $host =~ s|/.*$||;
  $client->ua->credentials($host, "OPSI Service", $self->{'server-usr'}, $self->{'server-pwd'});
  $client->ua->ssl_opts(verify_hostname => 0); # Do not check certificate hostname match

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
      $res = $res->result;
      if ((ref $res eq ref {}) && defined $res->{$self->{'fqdn'}}) {
        my $result = $res->{$self->{'fqdn'}};
        if (JSON::XS::is_bool($result)) {
          $res = $result;
        } elsif (defined $result->{'error'}) {
          $main::log->error("[OPSI] Error : ".$result->{'error'});
          die "Error while sending '".$action."' to '".$self->{'fqdn'}."' : ", $result->{'error'}."\n";
        } elsif (defined $result->{'result'}) {
          $res = $result->{'result'};
        } else {
          undef $res;
        }
      }
      return $res;
    }
  } else {
    $main::log->info("[OPSI] Status : ".$client->status_line);
    die "Status : ".$client->status_line."\n";
  }
}

1;

__END__
