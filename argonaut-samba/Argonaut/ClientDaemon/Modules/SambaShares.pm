#######################################################################
#
# Argonaut::ClientDaemon::Modules::SambaShares -- Creating Samba-Share Definitions from FusionDirectory
#
# Author : Thomas Niercke
# Version: 0.0.1
#
#  This program is free software; you can redistribute it and/or modify it under the terms of the GNU
#  General Public License as published by the Free Software Foundation; either version 2 of the License,
#  or (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without
#  even the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
#  General Public License for more details.
#
#  You should have received a copy of the GNU General Public License along with this program; if not,
#  write to the Free Software Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
#######################################################################
#
# This module will generate a file named /etc/samba/fustiondirectory.shares.conf
# and writes the shares defined from within FusionDirectory's Share-Plugin to it.
# The share's "Type:" has to be "samba" in order to be exported with this module.
#
# The samba (smbd) will also be reloaded automatically, but only when the
# md5-checksum of the newly created file differs from the md5-checkdum of the old file.
#
# To not disturb any existing samba-configuration the share-definitions are written
# to a seperate file which has to be includes in the [global]-Secion of your smb.conf
#
# However there are a few culpits in this very first version:
#    1. unless an update of the shares-plugin, all additional samba-options
#       goes to the "Option"-Field, seperated by a backslash (\).
#
#----------------------------------------------------------------------
# Format of the "Option"-Field:
# <options> \ <write-group[, ...]> \ <read-group[, ...]> \ <hide-share>
# where:
#    <options>     = reserved for future use. empty for now.
#    <write-group> = a list of comma-seperates group as defined in fusion-directory
#                    which members are granted read- and write-access.
#    <read-group>  = a list of comma-seperates group as defined in fusion-directory
#                    which members are granted read-only access.
#                    BEWARE: this is higher priority than <write-group>
#    <hide-share>  = if 1 then the share is created with the hidden flag (browseable = no)
#                    otherwise the share can be seen by anyone, regardless access to it.
#######################################################################

package Argonaut::ClientDaemon::Modules::SambaShares;
use strict;
use warnings;
use 5.008;
use Argonaut::Libraries::Common qw(:ldap :config);
use Digest::MD5 qw(md5_hex);
use File::Slurp;

my $base;
BEGIN {
  $base = (USE_LEGACY_JSON_RPC ? "JSON::RPC::Legacy::Procedure" : "JSON::RPC::Procedure");
}
use base $base;

=item trim
trims whitespaces from a given string
=cut
sub trim($) : Private {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

=item writeShareConfig
writes the shareconfiguration to /etc/samba/shares.conf

which then must be included in /etc/samba/smb.conf
=cut
sub writeShareConfig : Private {
  my ($SambaShares, $fname) = @_;
  my $serverName = $SambaShares->{'serverName'};
  my $serverIP   = $SambaShares->{'serverIP'};
  my $serverDesc = $SambaShares->{'description'};
  my $shares     = $SambaShares->{'shares'};

  $main::log->notice("SambaShares -> writing to file: $fname \n" );
  my $fd;
  open($fd, q{>}, $fname) or die "error while trying to open $fname";
  print $fd <<"END_SHARE";
;===============================================================
; This is a share-configuration file auto-generated
; using fusion-directory and argonaut-module 'SambaShares'
; see https://www.fusiondirectory.org for more information.
;
;===============================================================
END_SHARE

  foreach my $share (@{$shares}) {

    # remove the following 2 lines if the extension of the configuration
    # for the shares (ticket #5054) has been implenented.
    my ( $name, $desc, $fstype, $encoding, $path, $opt) = split(/\|/, $share);
    my ( $options, $write, $read, $hide)  = split(/\\/, $opt);

    # uncomment the following line, if ticket #5054 has been implemented
    #my ( $name, $desc, $fstype, $encoding, $path, $options, $write, $read, $hide) = split(/\|/, $share);

    next if ( lc(trim($fstype)) ne "samba" );

    my @wl = split(",", $write);

    my $validusers = "root";
    my $writelist = "root";
    if (length(trim($write)) > 0) {
      $writelist  = $writelist . ", @" . join(", @", @wl);
      $validusers = $validusers . ", @" . join(", @", @wl);
    }

    my $readlist = "";
    if (length(trim($read)) > 0) {
      $readlist   = "read list = \@" . join(", @", split(",",$read));
      $validusers = $validusers . ", \@" . join(", @", split(",",$read));
    }

    my $browseable = "yes";
    if ($hide eq "1") {
      $browseable = "no";
    }

    my $forcegroup = $wl[0];

    print $fd <<"END_SHARE";

;---------------------------------------------------------------
; Definition for Share '$name'
;---------------------------------------------------------------
[$name]
   comment = $desc
   path = $path
   browseable = $browseable
   $readlist
   write list = $writelist
#   force group = $forcegroup
   valid users = $validusers

   directory mask = 2770
   force directory mode = 2770
   directory security mask = 2770
   force directory security mode = 2770

   guest ok = no

END_SHARE

  } # of for

  close($fd);
}

# start of main
=item start
execute SambaShares complex operation on the computer
=cut
sub start : Public {
  $main::log->notice("SambaShares -> Module has been started");
  my ($server, $args) = @_;

  my $fname = "/etc/samba/fusiondirectory.shares.conf";
  my $old = md5_hex(read_file($fname));

  my $gotSamba = argonaut_get_generic_settings(
    'goShareServer',
    {
      'serverName'  => 'cn',
      'serverIP'    => 'ipHostNumber',
      'description' => 'description',
      'shares'      => ['goExportEntry', asref => 1]
    },
    $main::config, $main::config->{'client_ip'}
  );

  writeShareConfig( $gotSamba, $fname );

  my $new = md5_hex(read_file($fname));

  if ( $old eq $new ) {
    $main::log->notice("SambaShares -> nothing changed. finished here.");
  } else {
    $main::log->notice("SambaShares -> share-configuration changed. Reloading samba's smbd.");
    system("service smbd reload");
  }
}

1;

__END__
