#######################################################################
#
# Argonaut::Fuse::FAI
#
# Copyright (c) 2005,2006,2007 by Jan-Marek Glogowski <glogow@fbihome.de>
# Copyright (c) 2008 by Cajus Pollmeier <pollmeier@gonicus.de>
# Copyright (c) 2008,2009, 2010 by Jan Wenzel <wenzel@gonicus.de>
# Copyright (C) 2011 FusionDirectory project <contact@fusiondirectory.org>
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

package FAI;

use strict;
use warnings;

use 5.008;

use Net::LDAP;
use Net::LDAP::Util qw(:escape);
use Log::Handler;

use Exporter;
@ISA = ("Exporter");

my ($nfs_root, $nfs_opts, $fai_flags, $union);

my $cfg_defaults = {
  'nfs_root'  => [ \$nfs_root,  '/nfsroot' ],
  'nfs_opts'  => [ \$nfs_opts,  'nfs4' ],
  'fai_flags' => [ \$fai_flags, 'verbose,sshd,syslogd,createvt,reboot' ],
  'union' => [ \$union, 'unionfs' ],
};

my $log = Log::Handler->get_logger("argonaut-fuse");

sub get_module_info {
  # Add additional config sections
  return "Fully Automatic Installation";
};

sub get_config_sections {
  return $cfg_defaults;
}
  
sub get_pxe_config {
  my ($filename) = shift || return undef;
  my $result = undef;

  # Extract MAC from PXE filename      
  my $mac = $filename;                 
  $mac =~ tr/-/:/;
  $mac = substr( $mac, -1*(5*3+2) ); 

  # Prepare the ldap handle
reconnect:
  return undef if( ! &main::prepare_ldap_handle_retry
    ( 5 * $main::usec, -1, 0.5 * $main::usec, 1.2 ) );                                                                                                                                                                                                  

  # Search for the host to examine the FAI state
  my $mesg = $main::ldap_handle->search(
    base => "$main::ldap_base",
    filter => "(&(macAddress=$mac)(objectClass=FAIobject))",
    attrs => [ 'FAIstate', 'gotoBootKernel',
    'gotoKernelParameters', 'gotoLdapServer', 'cn', 'ipHostNumber' ] );

  if( 0 != $mesg->code ) {
    goto reconnect if( 81 == $mesg->code ); 
    $log->warning("$mac - LDAP MAC lookup error $mesg->code : $mesg->error\n");                                                                                                                                                                                  
    return undef; 
  } 

  my( $entry, $hostname, $status ); 
  if ($mesg->count() == 0) {
    $log->info("No FAI configuration for client with MAC ${mac}\n");
    return undef;
  } elsif ($mesg->count() == 1) { 
    $entry = ($mesg->entries)[0]; 
    $status = $entry->get_value( 'FAIstate' ); 
    $hostname = $entry->get_value( 'cn' );
  } elsif ($mesg->count() == 0) {
  } else { 
    $log->warning("$filename - MAC lookup error: too many LDAP results $mesg->count()\n"); 
    return undef; 
  } 

  my( $ldap_srv ); 

  # If we don't have a FAI state 
  if( (! defined($status)) || ("" eq $status) ) { 

    # Handle our default action 
    if ($main::dflt_init eq 'fallback') {
      # Remove PXE config and rely on 'default' fallback 
      if( -f "$main::tftp_root/$filename" ) { 
        if( ! $main::dry_run ) { 
          if( 0 == unlink( "$main::tftp_root/$filename" ) ) { 
            $log->error("$filename - removing from '$main::tftp_root' failed: $!\n"); 
            return undef; 
          } 
        } 
        else { 
          $log->info("$filename - dry-run - not removed from '$main::tftp_root'\n");
          return 0;  
        }
      } else { 
        $log->info("$filename - no LDAP status - continue PXE boot\n"); 
      }

      ############# break
      #############
      return 0;       
    } else {
      # "Super"-Default is 'localboot' - just use the built in disc
      $ldap_srv = $main::ldapuris[0] . '/' . $main::ldap_base;
      $status = 'localboot';

      $log->info("$filename - defaulting to localboot\n");
    }
  }

  my( $kernel, $cmdline, $host_dn );

  # Skip all data lookup, if we don't have an object
  goto skipped_data_lookup if( ! defined $entry );

  # Collect all vital data
  # Use first server defined in ldap
  my $new_ldap = defined($entry->get_value( 'gotoLdapServer', asref => 1 ))?@{ $entry->get_value( 'gotoLdapServer', asref => 1 ) }[0]:undef;
  $ldap_srv = $new_ldap if( defined $new_ldap );

  $kernel = $entry->get_value( 'gotoBootKernel' );
  $cmdline = $entry->get_value( 'gotoKernelParameters' );
  $host_dn = $entry->dn;

  # If any of these values isn't provided by the client check group membership
  if( (! defined $kernel)   || ("" eq $kernel)  ||
    (! defined $cmdline)  || ("" eq $cmdline) ||
    (! defined $ldap_srv) || ("" eq $ldap_srv) 
  ) { 
    $log->info("$filename - Information for PXE creation is missing\n");
    $log->info("$filename - Checking group membership...\n");

    my $filter = '(&(member=' . escape_filter_value($host_dn) . ')'
    . '(objectClass=gosaGroupOfNames)'
    . '(gosaGroupObjects=[*]))';
    $mesg = $main::ldap_handle->search(
      base => $main::ldap_base,
      filter => $filter,
      attrs => [ 'gotoBootKernel', 'gotoKernelParameters', 
      'gotoLdapServer', 'cn' ]);
    if( 0 != $mesg->code ) {
      goto reconnect if( 81 == $mesg->code );
      $log->warning("$filename - LDAP group lookup error $mesg->code: $mesg->error\n");
      return undef;   
    }

    # Get information from group membership
    my $group_entry;  
    if( 1 == $mesg->count ) {
      $group_entry = ($mesg->entries)[0];
      $kernel = $group_entry->get_value( 'gotoBootKernel' ) 
      if( ! defined $kernel );
      $cmdline = $group_entry->get_value( 'gotoKernelParameters' ) 
      if( ! defined $cmdline );
      $ldap_srv = @{$group_entry->get_value( 'gotoLdapServer', asref => 1)}[0]
      if( defined($group_entry->get_value( 'gotoLdapServer', asref => 1)) and not defined $ldap_srv );
    }

    # Jump over all checks - we should have sane defaults
    goto skipped_data_lookup if( $status =~ /^install-init$/ );

    # Check, if there is still missing information
    if( ! defined $kernel || ! defined $ldap_srv ) {
      my $single_log;
      if ($mesg->count == 0){
        $single_log = "$filename - no group membership found - aborting\n";
        $log->error($single_log);
      } elsif ($mesg->count == 1) {
        $single_log = "$filename - missing information in group - aborting\n";
        $log->error($single_log);
      } else {
        $single_log = "$filename - multiple group memberships found "
        . "($mesg->count) - aborting!\n";
        $log->error($single_log);
        foreach $group_entry ($mesg->entries) {
          $log->info("$filename - $group_entry->get_value('cn') - group_entry->dn()\n");
        }
      }

      $mesg  = "$filename - missing LDAP attribs:";
      $mesg .= ' gotoBootKernel' if( ! defined $kernel );
      $mesg .= ' gotoLdapServer' if( ! defined $ldap_srv ); 
      $mesg .= "\n";  

      $log->info($mesg);
      $main::last_log = $single_log;
      return undef;
    }
  } 
  

  # We jump here to omit group checks, since we should already have predefined
  # sane defaults, when we install initially
  skipped_data_lookup:

  $cmdline = "" if ( ! defined $cmdline );

  # Strip ldap parameter and all multiple and trailing spaces
  $cmdline =~ s/ldap(=[^\s]*[\s]*|[\s]*$|\s+)//g;
  $cmdline =~ s/[\s]+$//g;
  $cmdline =~ s/\s[\s]+/ /g;

  my $tftp_parent;
  if($main::tftp_root =~ /^(.*?)\/pxelinux.cfg$/) {
    $tftp_parent = $1;
  }

  # Get kernel and initrd from TFTP root
  if((not defined $kernel) || ('default' eq $kernel) ||
    ($tftp_parent and not -e "$tftp_parent/$kernel")) {
    $kernel = 'vmlinuz-install';
  }

  if( $kernel =~ m/^vmlinuz-(.*)$/ ) {
    if($tftp_parent and -e "$tftp_parent/initrd.img-$1" ) {
      $cmdline .= " initrd=initrd.img-$1";
    }
  }

  my $code = -1;
  my $chboot_cmd;
  my ($output);
  my $valid_status = 1;

  # Add NFS options and root, if available
  my $nfsroot_cmdline = ( defined $nfs_root && ($nfs_root ne '') );
  $cmdline .= " nfsroot=$nfs_root" if( $nfsroot_cmdline );
  if( defined $nfs_opts && ($nfs_opts ne '') ) {
    $cmdline .= ' nfsroot=' if( ! $nfsroot_cmdline );
    $cmdline .= ",$nfs_opts"
    if( defined $nfs_opts && ($nfs_opts ne '') );
  }

  if ($status =~ /^(install|install-init)$/) {
    $kernel = "kernel ${kernel}";
    $cmdline .= " FAI_ACTION=install FAI_FLAGS=${fai_flags} ip=dhcp"
    .  " devfs=nomount root=/dev/nfs boot=live union=$union";
  } elsif ($status =~ /^(error:|installing:)/) {
    # If we had an error, show an error message
    # The only difference is to install is "faierror" on cmdline
    my $faierror = ($status =~ /^installing:/) ? 'inst-' : '';
    $faierror .= (split( ':', $status ))[1];

    $kernel = "kernel ${kernel}";
    $cmdline .= " FAI_ACTION=install FAI_FLAGS=${fai_flags} ip=dhcp"
    .  " devfs=nomount root=/dev/nfs boot=live union=$union faierror:${faierror}";
  } elsif ($status eq 'softupdate') {
    # Softupdate has to be run by the client, so do a localboot
    $kernel = 'localboot 0';
    $cmdline = '';
  } elsif ($status eq 'sysinfo') {
    # Remove reboot flag in sysinfo mode - doesn't make sense
    my @sysflags = split( ',', ${fai_flags} );
    my $i = 0;
    while( $i < scalar( @sysflags ) ) {
      if( 'reboot' eq $sysflags[ $i ] ) {
        splice( @sysflags, $i, 1 );
        next;
      }
      $i++;
    }
    my $noreboot = join( ',', @sysflags );
    $kernel = "kernel ${kernel}";
    $cmdline .= " FAI_ACTION=sysinfo FAI_FLAGS=${noreboot} ip=dhcp"
    .  " devfs=nomount root=/dev/nfs boot=live union=$union";

  } elsif($status eq 'localboot') {
    $kernel = 'localboot 0';
    $cmdline = '';
  } else {
    $valid_status = 0;
  }

  if( $valid_status ) {
    $log->info("$filename - PXE status: $status\n");
    $code = &main::write_pxe_config_file( $hostname, $filename, $kernel, $cmdline );
  }

  if ($code == -1) {
    $log->error("$filename - unknown FAIstate: $status\n");
  }
  if ($code eq 0) {
    return time;
  }

  return $result;
}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
