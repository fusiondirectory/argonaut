package FAI;

use Exporter;
@ISA = ("Exporter");

use strict;
use warnings;

use Net::LDAP;
use Net::LDAP::Util qw(:escape);

my ($nfs_root, $nfs_opts, $fai_flags, $union);
my $cfg_defaults = {
	'nfs_root'  => [ \$nfs_root,  '/nfsroot' ],
	'nfs_opts'  => [ \$nfs_opts,  'nfs4' ],
	'fai_flags' => [ \$fai_flags, 'verbose,sshd,syslogd,createvt,reboot' ],
	'union' => [ \$union, 'unionfs' ],
};

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
		&main::daemon_log( sprintf( "$mac - LDAP MAC lookup error(%i): %s\n", 
				$mesg->code, $mesg->error ) );                                                                                                                                                                                  
		return undef; 
	} 

	my( $entry, $hostname, $status ); 
	if ($mesg->count() == 0) {
		&main::daemon_log("No FAI configuration for client with MAC ${mac}\n");
    return undef;
	} elsif ($mesg->count() == 1) { 
		$entry = ($mesg->entries)[0]; 
		$status = $entry->get_value( 'FAIstate' ); 
		$hostname = $entry->get_value( 'cn' );
	} elsif ($mesg->count() == 0) {
	} else { 
		&main::daemon_log( "$filename - MAC lookup error: too many LDAP results ("  
			. $mesg->count() . ")\n" ); 
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
						&main::daemon_log( "$filename - removing from '$main::tftp_root' failed: $!\n" ); 
						return undef; 
					} 
				} 
				else { 
					&main::daemon_log( "$filename - dry-run - not removed from '$main::tftp_root'\n" );
					return 0;  
				}
			} else { 
				&main::daemon_log( "$filename - no LDAP status - continue PXE boot\n" ); 
			}

			############# break
			#############
			return 0;       
		} else {
			# "Super"-Default is 'localboot' - just use the built in disc
			$ldap_srv = $main::ldapuris[0] . '/' . $main::ldap_base;
			$status = 'localboot';

			&main::daemon_log( "$filename - defaulting to localboot\n" );
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
		&main::daemon_log( "$filename - Information for PXE creation is missing\n" );
		&main::daemon_log( "$filename - Checking group membership...\n" );

		my $filter = '(&(member=' . escape_filter_value($host_dn) . ')'
		. '(objectClass=gosaGroupOfNames)'
		. '(gosaGroupObjects=[W]))';
		$mesg = $main::ldap_handle->search(
			base => $main::ldap_base,
			filter => $filter,
			attrs => [ 'gotoBootKernel', 'gotoKernelParameters', 
			'gotoLdapServer', 'cn' ]);
		if( 0 != $mesg->code ) {
			goto reconnect if( 81 == $mesg->code );
			&main::daemon_log( sprintf( "$filename - LDAP group lookup error(%i): %s\n",
					$mesg->code, $mesg->error ) );
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
        &main::daemon_log( $single_log );
      } elsif ($mesg->count == 1) {
        $single_log = "$filename - missing information in group - aborting\n";
        &main::daemon_log( $single_log );
      } else {
        $single_log = "$filename - multiple group memberships found "
        . "($mesg->count) - aborting!\n";
        &main::daemon_log( $single_log );
        foreach $group_entry ($mesg->entries) {
          &main::daemon_log( sprintf( "$filename - %s  (%s)\n",
              $group_entry->get_value( 'cn' ), $group_entry->dn() ) );
        }
      }

      $mesg  = "$filename - missing LDAP attribs:";
      $mesg .= ' gotoBootKernel' if( ! defined $kernel );
      $mesg .= ' gotoLdapServer' if( ! defined $ldap_srv ); 
      $mesg .= "\n";  

      &main::daemon_log( $mesg );
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
		&main::daemon_log( "$filename - PXE status: $status\n" );
		$code = &main::write_pxe_config_file( $hostname, $filename, $kernel, $cmdline );
	}

	if ($code == -1) {
		&main::daemon_log( "$filename - unknown FAIstate: $status\n" );
	}
	if ($code eq 0) {
		return time;
	}

	return $result;
}

1;

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
