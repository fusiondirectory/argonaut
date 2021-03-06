#######################################################################
#
# Argonaut::Fuse::FAI
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

package Argonaut::Fuse::Modules::FAI;

use strict;
use warnings;

use 5.008;

use Net::LDAP;
use Net::LDAP::Util qw(:escape);
use Log::Handler;

use Argonaut::Libraries::Common qw(:ldap :file);

use Exporter;
our @ISA = ("Exporter");

use constant USEC => 1000000;

my $log = Log::Handler->get_logger("argonaut-fuse");

sub get_module_info {
  # Add additional config sections
  return "Fully Automatic Installation";
}

sub get_module_settings {
  return argonaut_get_generic_settings(
    'argonautFuseFAIConfig',
    {
      'fai_flags' => "argonautFuseFaiFlags",
      'nfs_root'  => "argonautFuseNfsRoot",
    },
    $main::config,$main::config->{'client_ip'}
  );
}

sub get_pxe_config {
  my $class = shift;
  my ($filename) = shift || return;
  my $settings = get_module_settings();
  my $nfs_root  = $settings->{'nfs_root'};
  my $nfs_opts  = "";
  my $fai_flags = $settings->{'fai_flags'};
  my $union     = "aufs";
  my $mac       = argonaut_get_mac_pxe($filename);
  my $result = undef;

  # Search for the host to examine the FAI state
  my $infos = argonaut_get_generic_settings(
    'FAIobject',
    {
      'status'    => 'FAIstate',
      'hostname'  => 'cn',
    },
    $main::config,"(macAddress=$mac)"
  );

  if ($infos->{'locked'}) {
    # Locked machine: go to 'localboot'
    $infos->{'status'} = 'localboot';

    $log->info("$filename - is locked so localboot\n");
  } elsif ($infos->{'status'} eq '') {
    # If we don't have a FAI state
    # Handle our default action
    if ($main::default_mode eq 'fallback') {
      # Remove PXE config and rely on 'default' fallback
      if (-f "$main::tftp_root/$filename") {
        if (0 == unlink( "$main::tftp_root/$filename" )) {
          $log->error("$filename - removing from '$main::tftp_root' failed: $!\n");
          return;
        }
      } else {
        $log->info("$filename - no LDAP status - continue PXE boot\n");
      }

      return 0;
    } else {
      # "Super"-Default is 'localboot' - just use the built in disc
      $infos->{'status'}    = 'localboot';

      $log->info("$filename - defaulting to localboot\n");
    }
  }

  my $host_dn = $infos->{'dn'};

  my $tftp_parent;
  if ($main::tftp_root =~ /^(.*?)\/pxelinux.cfg$/) {
    $tftp_parent = $1;
  }

  # Get kernel and initrd from TFTP root
  $infos->{'kernel'} = 'vmlinuz-install';
  $infos->{'cmdline'} = ' initrd=initrd.img-install';

  my $chboot_cmd;
  my $output;
  my $valid_status = 1;

  # Add NFS options and root, if available
  my $nfsroot_cmdline = (defined $nfs_root && ($nfs_root ne ''));
  $infos->{'cmdline'} .= " nfsroot=$nfs_root" if( $nfsroot_cmdline );
  if (defined $nfs_opts && ($nfs_opts ne '')) {
    $infos->{'cmdline'} .= ' nfsroot=' if( ! $nfsroot_cmdline );
    $infos->{'cmdline'} .= ",$nfs_opts";
  }

  if ($infos->{'status'} =~ /^(install|install-init)$/) {
    $infos->{'kernel'}  = 'kernel '.$infos->{'kernel'};
    $infos->{'cmdline'} .= " ip=dhcp  root=/dev/nfs boot=live union=$union"
      .  " FAI_ACTION=${main::default_mode} FAI_FLAGS=${fai_flags}";
  } elsif ($infos->{'status'} =~ /^(error:|installing:)/) {
    # If we had an error, show an error message
    # The only difference is to install is "faierror" on cmdline
    my $faierror = ($infos->{'status'} =~ /^installing:/) ? 'inst-' : '';
    $faierror .= (split( ':', $infos->{'status'} ))[1];

    $infos->{'kernel'} = 'kernel '.$infos->{'kernel'};
    $infos->{'cmdline'} .= " ip=dhcp  root=/dev/nfs boot=live union=$union"
      .  " FAI_ACTION=${main::default_mode} FAI_FLAGS=${fai_flags} faierror:${faierror}";
  } elsif ($infos->{'status'} eq 'softupdate') {
    # Softupdate has to be run by the client, so do a localboot
    $infos->{'kernel'} = 'localboot 0';
    $infos->{'cmdline'} = '';
  } elsif ($infos->{'status'} eq 'sysinfo') {
    # Remove reboot flag in sysinfo mode - doesn't make sense
    my @sysflags = split( ',', ${fai_flags} );
    my $i = 0;
    while ($i < scalar(@sysflags)) {
      if ('reboot' eq $sysflags[ $i ]) {
        splice(@sysflags, $i, 1);
        next;
      }
      $i++;
    }
    my $noreboot = join( ',', @sysflags );
    $infos->{'kernel'} = 'kernel '.$infos->{'kernel'};
    $infos->{'cmdline'} .= " ip=dhcp  root=/dev/nfs boot=live union=$union"
      .  " FAI_ACTION=${main::default_mode} FAI_FLAGS=${noreboot} ";

  } elsif ($infos->{'status'} eq 'localboot') {
    $infos->{'kernel'} = 'localboot 0';
    $infos->{'cmdline'} = '';
  } else {
    $valid_status = 0;
  }

  if ($valid_status) {
    $log->info("$filename - PXE status: $infos->{'status'}\n");
    my $code = &main::write_pxe_config_file( $infos->{'hostname'}, $filename, $infos->{'kernel'}, $infos->{'cmdline'} );
    if ($code == 0) {
      return time;
    }
  } else {
    $log->error("$filename - unknown FAIstate: $infos->{'status'}\n");
  }

  return $result;
}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
