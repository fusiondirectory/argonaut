package LTSP;

use Exporter;
@ISA = ("Exporter");

use strict;
use warnings;

use Switch;
use Socket;
use Net::LDAP;
use Net::LDAP::Util qw(:escape);

sub get_module_info {
	return "Linux Terminal Server Project";
};

my $admin;
my $password;
my $server;
my $cfg_defaults = {
	# 'dflt_init' => [ my	$dflt_init, 'install' ], # 'install', 'fallback';;
	'server' => [ \$server, 'localhost' ],
};

sub get_config_sections {
	return $cfg_defaults;
}

# Check if this module should handle this client
# return 1 if this is the case, 0 otherwise
sub has_pxe_config {
        my ($filename) = shift || return undef;
        my $result = 0;

        &main::daemon_log("ch $$: got filename ${filename}");

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
		filter => "(&(macAddress=$mac)(objectClass=gotoTerminal))",
		attrs => [ 'gotoTerminalPath', 'gotoBootKernel',
		'gotoKernelParameters', 'gotoLdapServer', 'cn' ] );


	if( 0 != $mesg->code ) {
		goto reconnect if( 81 == $mesg->code );
		&main::daemon_log( sprintf( "$mac - LDAP MAC lookup error(%i): %s\n",
				$mesg->code, $mesg->error ) );

		return undef;
	}

        if($mesg->count() == 1) {
                &main::daemon_log("Found LTSP configuration for client with MAC ${mac}\n");
                $result = 1;
        } else {
                &main::daemon_log("No LTSP configuration for client with MAC ${mac}\n");
        }

        return $result;
}


# Do everything that is needed, i.e. write the pxelinux.cfg file
sub get_pxe_config {
        my ($filename) = shift || return undef;
	my $cmdline;
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
                filter => "(&(macAddress=$mac)(objectClass=gotoTerminal))",
                attrs => [ 'gotoTerminalPath', 'gotoBootKernel',
                'gotoKernelParameters', 'cn', 'gotoLdapServer' ] );


        if( 0 != $mesg->code ) {
                goto reconnect if( 81 == $mesg->code );
                &main::daemon_log( sprintf( "$mac - LDAP MAC lookup error(%i): %s\n",
                                $mesg->code, $mesg->error ) );

                return undef;
        }

        my( $entry, $hostname );
        if ($mesg->count() == 1) {
                $entry = ($mesg->entries)[0];
                $hostname = $entry->get_value( 'cn' );
        } elsif ($mesg->count() == 0) {
                &main::daemon_log("No LTSP configuration for client with MAC ${mac}\n");
		return undef;
	} else {
                &main::daemon_log( "$filename - MAC lookup error: too many LDAP results ("
                        . $mesg->count() . ")\n" );
                return undef;
        }


	my $kernel= $entry->get_value( 'gotoBootKernel' );
	my $nfsroot = $entry->get_value( 'gotoTerminalPath' );
	$cmdline= $entry->get_value( 'gotoKernelparameters' );
	my $ldap_srv= $entry->get_value( 'gotoLDAPServer' );

	# Check group
        my $host_dn = $entry->dn;

        # If any of these values isn't provided by the client check group membership
        if( (! defined $kernel)   || ("" eq $kernel)  ||
                (! defined $cmdline)  || ("" eq $cmdline) ||
                (! defined $nfsroot)  || ("" eq $nfsroot) ||
                (! defined $ldap_srv) || ("" eq $ldap_srv)
        ) {
                &main::daemon_log( "$filename - Information for PXE creation is missing\n" );
                &main::daemon_log( "$filename - Checking group membership...\n" );

                my $filter = '(&(member=' . escape_filter_value($host_dn) . ')'
                . '(objectClass=gosaGroupOfNames)'
                . '(gosaGroupObjects=[T]))';
                $mesg = $main::ldap_handle->search(
                        base => $main::ldap_base,
                        filter => $filter,
                        attrs => [ 'gotoBootKernel', 'gotoKernelParameters',
                        'gotoLdapServer', 'cn', 'gotoTerminalPath' ]);
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
                        $ldap_srv = $group_entry->get_value( 'gotoLdapServer' )
                        if( ! defined $ldap_srv );
                        $nfsroot = $group_entry->get_value( 'gotoTerminalPath' )
                        if( ! defined $nfsroot );
                }

                # Check, if there is still missing information
                if( ! defined $cmdline || ! defined $kernel || ! defined $ldap_srv || ! defined $nfsroot ) {
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
                        $mesg .= ' gotoKernelParameters' if( ! defined $cmdline );
                        $mesg .= ' gotoLdapServer' if( ! defined $ldap_srv );
                        $mesg .= ' gotoTerminalPath' if( ! defined $nfsroot );
                        $mesg .= "\n";

                        &main::daemon_log( $mesg );
                        return undef;
                }
        }

	# Compile initrd name
	my $initrd= $kernel;
	$initrd =~ s/^[^-]+-//;
	$initrd = "initrd.img-$initrd";

	# Set NFSROOT
	if (not defined $nfsroot) {
		$nfsroot= "";
	} else {
		# Transform to IP if possible
		my $server= $nfsroot;
		my $path= $nfsroot;
		$server =~ s/:.*$//;
		$path =~ s/^[^:]+://;
		if ($server !~ /^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$/ ){
			$server = inet_ntoa(inet_aton($server));
		}

		$nfsroot= "nfsroot=$server:$path";
	}

	# Set kernel parameters
	if (not defined $cmdline) {
		$cmdline= "";
	}

	# Assign commandline
	$cmdline = "ro initrd=$initrd ip=dhcp boot=nfs root=/dev/nfs $nfsroot $cmdline";

&main::daemon_log( "DEBUG: Kernel ($kernel) $cmdline\n" );

	&main::daemon_log( "$filename - PXE status: boot\n" );
	my $code = &main::write_pxe_config_file( undef, $filename, "kernel $kernel", $cmdline );
	if ( $code == 0) {
		return time;
	} 
	if ( $code == -1) {
		&main::daemon_log( "$filename - unknown error\n" );
	}

	# Return our result
	return $result;
}

1;
