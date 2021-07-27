#######################################################################
#
# Argonaut::Server::Modules::Argonaut -- Argonaut client module
#
# Copyright (C) 2012-2016 FusionDirectory project
#
# Authors: Côme BERNIGAUD
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

package Argonaut::Server::Modules::Argonaut;

use strict;
use warnings;

use 5.008;

use Argonaut::Libraries::Common qw(:ldap :file :config :string);

use if (USE_LEGACY_JSON_RPC),     'JSON::RPC::Legacy::Client';
use if not (USE_LEGACY_JSON_RPC), 'JSON::RPC::Client';

my @unlocked_actions = ['System.halt', 'System.reboot'];

sub new
{
  my ($class) = @_;
  my $self = {};
  bless( $self, $class );
  return $self;
}

sub handle_client {
  my ($self, $mac,$action) = @_;

  $self->{target} = $mac;

  if ($action =~ m/^Deployment.(reboot|wake)$/) {
    $action =~ s/^Deployment./System./;
  } elsif ($action =~ m/^Deployment./) {
    $main::log->debug("[Argonaut] Can't handle Deployment actions");
    return 0;
  }

  if ($action eq 'System.wake') {
    $self->{action} = $action;
    return 1;
  }

  eval { #try
    my $settings = argonaut_get_client_settings($main::config,"(macAddress=$mac)");
    %$self = %$settings;
    $self->{action} = $action;
    $self->{target} = $mac;
  };
  if ($@) { #catch
    $main::log->debug("[Argonaut] Can't handle client : $@");
    return 0;
  };
  $self->{cacertfile} = $main::server_settings->{cacertfile};
  $self->{token}      = $main::server_settings->{token};
  # We take a lower timeout than the server so that it's possible to return the result
  $self->{timeout}    = $main::server_settings->{timeout} - 2;
  if ($self->{timeout} <= 0) {
    $self->{timeout} = 1;
  }

  return 1;
}

=pod
=item do_action
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub do_action {
  my ($self, $params) = @_;
  my $action = $self->{action};

  if ($action eq 'System.wake') {
    main::wakeOnLan($self->{'mac'});
    return 1;
  }

  if ($self->{'locked'} && (grep {$_ eq $action} @unlocked_actions)) {
    die 'This computer is locked';
  }

  if ($action eq 'ping') {
    my $ok  = 'OK';
    my $res = '';
    eval {
      $res = $self->launch('echo',$ok);
    };
    return ($res eq $ok);
  } else {
    return $self->launch($action,$params);
  }
}

=pod
=item launch
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub launch { # if ip pings, send the request
  my ($self, $action,$params) = @_;

  if ($action =~ m/^[^.]+\.[^.]+$/) {
    $action = 'Argonaut.ClientDaemon.Modules.'.$action;
  }

  my $ip = $self->{'ip'};
  # this line is only needed when debugging stuff on localhost
  #$ip = "localhost";

  $main::log->info("sending action $action to $ip");

  my $client;
  if (USE_LEGACY_JSON_RPC) {
    $client = new JSON::RPC::Legacy::Client;
  } else {
    $client = new JSON::RPC::Client;
  }
  $client->version('1.0');
  if ($self->{'protocol'} eq 'https') {
    if ($client->ua->can('ssl_opts')) {
      $client->ua->ssl_opts(
        verify_hostname   => 1,
        SSL_ca_file       => $self->{'cacertfile'},
        SSL_verifycn_name => $self->{'certcn'}
      );
      $client->ua->credentials($ip.":".$self->{'port'}, "JSONRPCRealm", "", argonaut_gen_ssha_token($self->{'token'}));
    }
  }
  $client->ua->timeout($self->{timeout});

  my $callobj = {
    method  => $action,
    params  => [$params],
  };

  my $res;
  eval {
    $res = $client->call($self->{'protocol'}."://".$ip.":".$self->{'port'}, $callobj);
  };
  if ($@) {
    if ($client->status_line =~ m/^(4|5)\d\d/) {
      $main::log->info("Status : ".$client->status_line);
      die $client->status_line."\n";
    } else {
      $main::log->error("Error : ".$@);
      die $@."\n";
    }
  }

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
