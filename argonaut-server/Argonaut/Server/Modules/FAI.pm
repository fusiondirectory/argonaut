#######################################################################
#
# Argonaut::Server::Modules::FAI -- FAI client module
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

package Argonaut::Server::Modules::FAI;

use strict;
use warnings;

use 5.008;

use Argonaut::Common qw(:ldap :file);

my @fai_actions = ["Deployment.reinstall", "Deployment.update", "Deployment.wake", "Deployment.reboot"];

sub handle_client {
  my ($obj, $mac, $action) = @_;

  if (grep {$_ eq $action} @fai_actions) {
    my $ip = main::getIpFromMac($mac);
    eval { #try
      argonaut_get_generic_settings(
        'FAIobject', {'state' => "FAIstate"},
        $main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$ip
      );
    };
    if ($@) { #catch
      return 0;
    };
    return 1;
  } else {
    return 0;
  }
}

=pod
=item do_action
Execute a JSON-RPC method on a client which the ip is given.
Parameters : ip,action,params
=cut
sub do_action {
  my ($obj, $kernel,$heap,$session,$target,$action,$taskid,$params) = @_;

  my $substatus = $obj->handler_fai($kernel,$session,$taskid,$target,$action,$params);
  if(defined $taskid) {
    $heap->{tasks}->{$taskid}->{substatus} = $substatus;
  }
  return 0;
}

=pod
item handler_fai
Put the right boot mode in the ldap and send the right thing to the client.
Parameters : the targetted mac address, the action received, the args received for it (args are currently unused).
=cut
sub handler_fai {
  my($obj, $kernel,$session,$taskid,$target,$action,$args) = @_;
  my $fai_state = {
    "Deployment.reinstall"  => "install",
    "Deployment.update"     => "softupdate",
    "Deployment.reboot"     => "localboot",
    "Deployment.wake"       => "localboot"
  };

  my $need_reboot = ($action ne "Deployment.wake");

  $obj->flag($target,$fai_state->{$action});

  eval { # try
    if($need_reboot) {
      $kernel->call($session=>action=>$taskid,"System.reboot",$target,{'args'=>[]});
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
    filter => "macAddress=$target",
    attrs => [ 'FAIstate' ]
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

  $mesg = $ldap->modify($dn, replace => {"FAIstate" => $fai_state});

  $mesg->code && die "Error while setting FAIstate for target address '$target' :".$mesg->error;

  $mesg = $ldap->unbind;   # take down session
}

1;

__END__
