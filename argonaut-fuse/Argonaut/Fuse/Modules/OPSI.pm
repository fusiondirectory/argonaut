#######################################################################
#
# Argonaut::Fuse::OPSI
#
# Copyright (c) 2005,2006,2007 by Jan-Marek Glogowski <glogow@fbihome.de>
# Copyright (c) 2008 by Cajus Pollmeier <pollmeier@gonicus.de>
# Copyright (c) 2008,2009, 2010 by Jan Wenzel <wenzel@gonicus.de>
# Copyright (C) 2011-2016 FusionDirectory project
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

package Argonaut::Fuse::Modules::OPSI;

use strict;
use warnings;

use 5.008;

use Argonaut::Libraries::Common qw(:ldap :file :config);

use Net::LDAP;
use Net::LDAP::Util qw(:escape);
use if (USE_LEGACY_JSON_RPC),     'JSON::RPC::Legacy::Client';
use if not (USE_LEGACY_JSON_RPC), 'JSON::RPC::Client';
use Log::Handler;

use Exporter;
our @ISA = ("Exporter");

my $sclient="";

my $log = Log::Handler->get_logger("argonaut-fuse");

sub get_module_info {
  return "Automatic Windows Installation";
}

sub get_module_settings {
  return argonaut_get_generic_settings(
    'argonautFuseOPSIConfig',
    {
      'admin'     => "argonautFuseOpsiAdmin",
      'password'  => "argonautFuseOpsiPassword",
      'server'    => "argonautFuseOpsiServer",
      'lang'      => "argonautFuseOpsiLang"
    },
    $main::config,$main::config->{'client_ip'}
  );
}

sub get_pxe_config {
  my $class = shift;
  my ($filename) = shift || return;
  my $settings = get_module_settings();
  my $lang  = $settings->{'lang'};
  my $mac   = argonaut_get_mac_pxe($filename);

  my $opsi_url = "https://".$settings->{'admin'}.":".$settings->{'password'}."\@".$settings->{'server'}.":4447/rpc";
  my $opsi_client;
  if (USE_LEGACY_JSON_RPC) {
    $opsi_client = new JSON::RPC::Legacy::Client;
  } else {
    $opsi_client = new JSON::RPC::Client;
  }
  my $result = undef;

  my $state   = 0;
  my $status  = "localboot";
  my $kernel  = "kernel opsi-install";
  my $product = "";
  my $cmdline;

  # Search for the host to examine the lock state
  my $infos = argonaut_get_generic_settings(
    'opsiClient',
    {
    },
    $main::config, "(macAddress=$mac)"
  );
  
  if ($infos->{'locked'}) {
    # Localboot
    $status   = 'localboot (locked)';
    $kernel   = 'localboot 0';
    $cmdline  = '';
  } else {
    # Load actions
    my $callobj = {
      method  => 'getClientIdByMac',
      params  => [$mac],
      id  => 1,
    };
    my $res     = $opsi_client->call($opsi_url, $callobj);
    if ($res) {
      if ($res->is_error) {
        $log->error("ch $$: Error : $res->error_message\n");
      } else {
        $sclient = $res->result;
        $callobj = { method  => 'getNetBootProductStates_hash', params  => [ $sclient ], id  => 2, };
        my $res2 = $opsi_client->call($opsi_url, $callobj);
        if ($res2) {
          if ($res2->is_error) {
            $log->error("ch $$: Error : ". $res2->error_message."\n");
          } else {
              foreach my $element (@{$res2->result->{$sclient}}){
              if(
                $element->{'actionRequest'} ne '' &&
                $element->{'actionRequest'} ne 'undefined' &&
                $element->{'actionRequest'} ne 'none' ) {
                  $state= 1;
                  $status= "install";
                  $product= "product=".$element->{'productId'};
                  last;
                }
              }
            }
        } else {
          $log->error("ch $$: Error : $opsi_client->status_line\n");
        }

        if ($state) {
          # Installation requested
          my $service= "";
          my $pckey= "";

          # Load pc key
          $callobj = { method  => 'getOpsiHostKey', params  => [ $sclient ], id  => 4, };
          $res = $opsi_client->call($opsi_url, $callobj);
          if (defined $res->result) {
            $pckey= "pckey=".$res->result;
            $log->info("setting pckey for $sclient\n");
          } else {
            $log->warning("no pc key for $sclient found\n");
          }

          # Load depot server for this client
          $callobj = { method  => 'getDepotId', params  => [ $sclient ], id  => 5, };
          $res = $opsi_client->call($opsi_url, $callobj);
          if (defined $res->result){
            $service= "service=".$res->result;
            $log->info("setting depot server for $sclient to $service\n");
          } else {
            $log->info("no depot server for $sclient defined\n");
          }
          $cmdline = "noapic lang=$lang ramdisk_size=175112 init=/etc/init initrd=opsi-root.gz reboot=b video=vesa:ywrap,mtrr $service $pckey vga=791 quiet splash $product";
        } else {
          # Localboot
          $kernel = 'localboot 0';
          $cmdline = '';
        }
      }
    } else {
      $log->error("ch $$: Error : $opsi_client->status_line\n");
    }
  }


  $log->info("$filename - PXE status: $status\n");
  my $code = &main::write_pxe_config_file( $sclient, $filename, $kernel, $cmdline );
  if ($code == 0) {
    return time;
  }

  if ($code == -1) {
    $log->info("$filename - unknown state: $status\n");
  }

  # Return our result
  return $result;
}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
