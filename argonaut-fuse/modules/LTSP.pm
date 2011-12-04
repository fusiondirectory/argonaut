#######################################################################
#
# Argonaut::Fuse::LTSP
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

package LTSP;

use strict;
use warnings;

use 5.008;

use Switch;
use Socket;
use Net::LDAP;
use Net::LDAP::Util qw(:escape);
use Log::Handler;

use Argonaut::Common qw(:file);

use Exporter;
our @ISA = ("Exporter");

use constant USEC => 1000000;

my $server;

my $log = Log::Handler->get_logger("argonaut-fuse");

sub get_module_info {
  return "Linux Terminal Server Project";
};

sub get_pxe_config {
  my ($filename) = shift || return undef;
  my $cmdline;
  my $result = undef;

  my $mac = argonaut_get_mac_pxe($filename);

  # Prepare the ldap handle
  reconnect:
  return undef if (! &main::prepare_ldap_handle_retry(5 * USEC, -1, 0.5 * USEC, 1.2));

        # Search for the host to examine the LTSP entry
        my $mesg = $main::ldap_handle->search(
            base => "$main::ldap_base",
            filter => "(&(macAddress=$mac)(objectClass=gotoTerminal))",
            attrs => [ 
                'gotoTerminalPath', 'gotoBootKernel',
                'gotoKernelParameters', 'cn', 'gotoLdapServer' ]);

        if (0 != $mesg->code) {
          goto reconnect if (81 == $mesg->code);
          $log->warning("$mac - LDAP MAC lookup error $mesg->code: $mesg->error\n");
          return undef;
        }

        my ($entry, $hostname);
        if ($mesg->count() == 1) {
          $entry = ($mesg->entries)[0];
          $hostname = $entry->get_value ('cn');
        } elsif ($mesg->count() == 0) {
            $log->info("No LTSP configuration for client with MAC ${mac}\n");
            return undef;
          } else {
              $log->warning("$filename - MAC lookup error: too many LDAP results $mesg->count()\n");
              return undef;
            }

        my $kernel= $entry->get_value ('gotoBootKernel');
        my $nfsroot = $entry->get_value ('gotoTerminalPath');
        $cmdline= $entry->get_value ('gotoKernelparameters');
        my $ldap_srv= $entry->get_value ('gotoLDAPServer');

        # Check group
        my $host_dn = $entry->dn;

        # If any of these values isn't provided by the client check group membership
        if ((! defined $kernel) || ("" eq $kernel) ||
            (! defined $cmdline)  || ("" eq $cmdline) ||
            (! defined $nfsroot)  || ("" eq $nfsroot) ||
            (! defined $ldap_srv) || ("" eq $ldap_srv)) {
              $log->warning("$filename - Information for PXE creation is missing\n");
              $log->warning("$filename - Checking group membership...\n");

              my $filter = '(&(member=' . escape_filter_value($host_dn) . ')'
                . '(objectClass=gosaGroupOfNames)'
                . '(gosaGroupObjects=[T]))';
              $mesg = $main::ldap_handle->search(
                base => $main::ldap_base,
                filter => $filter,
                attrs => ['gotoBootKernel', 'gotoKernelParameters',
                        'gotoLdapServer', 'cn', 'gotoTerminalPath']);
                if (0 != $mesg->code) {
                        goto reconnect if (81 == $mesg->code);
                        $log->error("$filename - LDAP group lookup error $mesg->code: $mesg->error\n");
                        return undef;
                }

                # Get information from group membership
                my $group_entry;
                if (1 == $mesg->count) {
                  $group_entry = ($mesg->entries)[0];
                  $kernel = $group_entry->get_value('gotoBootKernel')
                  if (! defined $kernel);
                    $cmdline = $group_entry->get_value('gotoKernelParameters')
                    if (! defined $cmdline);
                        $ldap_srv = $group_entry->get_value('gotoLdapServer')
                        if (! defined $ldap_srv);
                        $nfsroot = $group_entry->get_value('gotoTerminalPath')
                        if (! defined $nfsroot);
                }

                # Check, if there is still missing information
                if (! defined $cmdline || ! defined $kernel || ! defined $ldap_srv || ! defined $nfsroot ) {
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
                          $log->info("$filename - $group_entry->get_value('cn') - $group_entry->dn()\n");
                        }
                      }

                      $mesg  = "$filename - missing LDAP attribs:";
                      $mesg .= ' gotoBootKernel' if( ! defined $kernel );
                      $mesg .= ' gotoKernelParameters' if( ! defined $cmdline );
                      $mesg .= ' gotoLdapServer' if( ! defined $ldap_srv );
                      $mesg .= ' gotoTerminalPath' if( ! defined $nfsroot );
                      $mesg .= "\n";

                      $log->warning($mesg);
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

    $log->debug("Kernel ($kernel) $cmdline\n");

    $log->info("$filename - PXE status: boot\n");
    my $code = &main::write_pxe_config_file( undef, $filename, "kernel $kernel", $cmdline );
    
    if ($code == 0) {
      return time;
    } 
    
    if ($code == -1) {
      $log->error("$filename - unknown error\n");
    }

    # Return our result
    return $result;
}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
