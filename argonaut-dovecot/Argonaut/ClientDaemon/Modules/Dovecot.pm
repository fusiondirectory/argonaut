#######################################################################
#
# Argonaut::ClientDaemon::Modules::Dovecot -- Dovecot mailbox creation
#
# Copyright (C) 2013 FusionDirectory project <contact@fusiondirectory.org>
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

package Argonaut::ClientDaemon::Modules::Dovecot;

use strict;
use warnings;

use 5.008;

use base qw(JSON::RPC::Procedure); # requires Perl 5.6 or later

=item create_mailbox
Creates the folder so that Dovecot will be able of creating the mailbox on first connection
=cut
sub create_mailbox : Public {
  my ($s, $args) = @_;
  my ($account_id) = @{$args};
  $main::log->notice("Creating mailbox folder for user $account_id");
  mkdir get_maildir().'/'.$account_id or die 'Could not create directory: '.$!;
  return 1;
}

sub get_maildir : Private {
  my $ldapinfos = argonaut_ldap_init ($main::ldap_configfile, 0, $main::ldap_dn, 0, $main::ldap_password);

  my $mesg = $ldapinfos->{'HANDLE'}->search( # perform a search
    base   => $ldapinfos->{'BASE'},
    filter => "(&(objectClass=fdDovecotServer)(ipHostNumber=".$main::client_settings->{'ip'}."))",
    attrs => [ 'fdDovecotMailDir' ]
  );

  if (scalar($mesg->entries)==1) {
    return ($mesg->entries)[0]->get_value("fdDovecotMailDir");
  }
  die "Dovecot server not found in LDAP";
}

1;

__END__
