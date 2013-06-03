#######################################################################
#
# Argonaut::Server::Modules::FAI -- FAI client module
#
# Copyright (C) 2012-2013 FusionDirectory project <contact@fusiondirectory.org>
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

package Argonaut::Server::Modules::FAI;

use strict;
use warnings;

use 5.008;

use Argonaut::Common qw(:ldap :file);

my @fai_actions = ("Deployment.reinstall", "Deployment.update", "Deployment.wake", "Deployment.reboot");

sub new
{
  my ($class) = @_;
  my $self = {};
  bless( $self, $class );
  return $self;
}

sub handle_client {
  my ($self, $mac, $action) = @_;

  if (grep {$_ eq $action} @fai_actions) {
    my $ip = main::getIpFromMac($mac);
    eval { #try
      my $settings = argonaut_get_generic_settings(
        'FAIobject', {'state' => "FAIstate"},
        $main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip
      );
      %$self = %$settings;
      $self->{action} = $action;
    };
    if ($@) { #catch
      $main::log->debug("[FAI] Can't handle client : $@");
      return 0;
    };
    return 1;
  } else {
    $main::log->debug("[FAI] Can't handle action '$action'");
    return 0;
  }
}

=pod
=item do_action
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub do_action {
  my ($self, $params) = @_;

  if ($self->{'locked'}) {
    die 'This computer is locked';
  }

  my $substatus = $self->handler_fai($self->{taskid},$self->{action},$params);
  $self->{task}->{substatus} = $substatus;
  return 0;
}

=pod
item handler_fai
Put the right boot mode in the ldap and send the right thing to the client.
Parameters : the targetted mac address, the action received, the args received for it (args are currently unused).
=cut
sub handler_fai {
  my($self, $taskid,$action,$args) = @_;
  my $fai_state = {
    "Deployment.reinstall"  => "install",
    "Deployment.update"     => "softupdate",
    "Deployment.reboot"     => "localboot",
    "Deployment.wake"       => "localboot"
  };

  my $need_reboot = ($action ne "Deployment.wake");

  $self->flag($fai_state->{$action});

  eval { # try
    if($need_reboot) {
      $self->{launch_actions} = [["System.reboot", [$self->{'mac'}], {'args' => []}]];
      return "rebooting";
    } else {
      main::wakeOnLan($self->{'mac'});
      return "wake on lan";
    }
  };
  if ($@) { # catch
    $main::log->notice("Got $@ while trying to reboot, trying wake on lan");
    main::wakeOnLan($self->{'mac'});
    return "wake on lan";
  };
}

=item

=cut
sub flag {
  my ($self, $fai_state) = @_;
  my $ldapinfos = argonaut_ldap_init ($main::ldap_configfile, 0, $main::ldap_dn, 0, $main::ldap_password);

  if ($ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my $mesg = $ldapinfos->{'HANDLE'}->modify($self->{'dn'}, replace => {"FAIstate" => $fai_state});

  $mesg->code && die "Error while setting FAIstate for object '".$self->{'dn'}."' :".$mesg->error;

  $mesg = $ldapinfos->{'HANDLE'}->unbind;   # take down session
}

1;

__END__
