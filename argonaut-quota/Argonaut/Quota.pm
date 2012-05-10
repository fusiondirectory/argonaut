#######################################################################
#
# Argonaut::Quota packages - functions to get info for quota from ldap
#
# Copyright (c) 2012 FusionDirectory project
#
# Author: Côme BERNIGAUD
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
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#######################################################################

package Argonaut::Quota;

use strict;
use warnings;

use 5.008;

BEGIN
{
  use Exporter ();
  use vars qw(%EXPORT_TAGS @ISA $VERSION);
  $VERSION = '2012-04-24';
  @ISA = qw(Exporter);

  %EXPORT_TAGS = ();

  Exporter::export_ok_tags(keys %EXPORT_TAGS);
}

=head1
Warnquota

Write warnquota and quotatab files
=cut
sub warnquota {
  my ($ldap_configfile,$ldap_dn,$ldap_password,$ip,$warnquota_file,$quotatab_file) = @_;

  open (WARNQUOTA, ">", $warnquota_file) or die "Could not open file $warnquota_file";
  open (QUOTATAB, ">", $quotatab_file) or die "Could not open file $quotatab_file";

  my $settings = get_quota_settings($ldap_configfile,$ldap_dn,$ldap_password,$ip);

  # edition of warnquota.conf
  print WARNQUOTA "MAIL_CMD        = ".$settings->{'mail_cmd'}."\n";
  print WARNQUOTA "CC_TO           = ".$settings->{'cc_to'}."\n";
  print WARNQUOTA "FROM            = ".$settings->{'from'}."\n";
  print WARNQUOTA "SUBJECT         = ".$settings->{'subject'}."\n";
  # Support email for assistance (included in generated mail)
  print WARNQUOTA "SUPPORT         = ".$settings->{'support'}."\n";
  # Support phone for assistance (included in generated mail)
  # The message to send
  print WARNQUOTA "MESSAGE         = ".$settings->{'message'}."\n";
  # The signature of the mail
  print WARNQUOTA "SIGNATURE       = ".$settings->{'signature'}."\n";
  # character set the email is to be send in
  print WARNQUOTA "CHARSET         = ".$settings->{'charset'}."\n";
  # add LDAP support
  print WARNQUOTA "LDAP_MAIL             = true"."\n";
  print WARNQUOTA "LDAP_SEARCH_ATTRIBUTE = ".$settings->{'ldap_searchattribute'}."\n";
  print WARNQUOTA "LDAP_MAIL_ATTRIBUTE   = mail\n";
  print WARNQUOTA "LDAP_BASEDN           = ".$settings->{'ldap_basedn'}."\n";
  print WARNQUOTA "LDAP_HOST             = ".$settings->{'ldap_host'}."\n";
  print WARNQUOTA "LDAP_PORT             = ".$settings->{'ldap_port'}."\n";
  print WARNQUOTA "LDAP_USER_DN          = ".$settings->{'ldap_userdn'}."n";
  print WARNQUOTA "LDAP_PASSWORD         = ".$settings->{'ldap_userpwd'}."\n";
  # end of warnquota.conf

  # Begin of quota tab edition
  my @quotaDeviceParameters = $settings->{'device_parameters'};
  if ($#quotaDeviceParameters >= 0) {
    foreach (@quotaDeviceParameters) {
      my @quotaDeviceParameter = split /:/;
      print QUOTATAB $quotaDeviceParameter[0].":".$quotaDeviceParameter[2]."\n";
    }
  }
  # end of quota tab edition
}

sub get_quota_settings {
  my ($ldap_configfile,$ldap_dn,$ldap_password,$ip) = @_;

  my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);

  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my ($ldap,$ldap_base) = ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'});

  my $mesg = $ldap->search( # perform a search
            base   => $ldap_base,
            filter => "(&(objectClass=quotaService)(ipHostNumber=$ip))",
            attrs => [  'quotaDeviceParameters',
                        'quotaLdapSearchIdAttribute',
                        'quotaLdapServerURI','quotaLdapServerUserDn',
                        'quotaLdapServerUserPassword','quotaMsgCharsetSupport',
                        'quotaMsgContactSupport','quotaMsgContentSupport',
                        'quotaMsgFromSupport','quotaMsgSignatureSupport',
                        'quotaMsgSubjectSupport','quotaMailCommand',
                        'quotaCarbonCopyMail' ]
            );

  my $client_settings = {};

  if(scalar($mesg->entries)==1) {
    my $uri = URI->new(($mesg->entries)[0]->get_value('quotaLdapServerURI'));
    $client_settings = {
      'mail_cmd'              => ($mesg->entries)[0]->get_value("quotaMailCommand"),
      'cc_to'                 => ($mesg->entries)[0]->get_value("quotaCarbonCopyMail"),
      'from'                  => ($mesg->entries)[0]->get_value("quotaMsgFromSupport"),
      'subject'               => ($mesg->entries)[0]->get_value("quotaMsgSubjectSupport"),
      'support'               => ($mesg->entries)[0]->get_value("quotaMsgContactSupport"),
      'message'               => ($mesg->entries)[0]->get_value("quotaMsgContentSupport"),
      'signature'             => ($mesg->entries)[0]->get_value("quotaMsgSignatureSupport"),
      'charset'               => ($mesg->entries)[0]->get_value("quotaMsgCharsetSupport"),
      'ldap_basedn'           => $uri->dn,
      'ldap_host'             => $uri->host,
      'ldap_port'             => $uri->port,
      'ldap_searchattribute'  => ($mesg->entries)[0]->get_value("quotaLdapSearchIdAttribute"),
      'ldap_userdn'           => ($mesg->entries)[0]->get_value("quotaLdapServerUserDn"),
      'ldap_userpwd'          => ($mesg->entries)[0]->get_value("quotaLdapServerUserPassword"),
      'device_parameters'     => ($mesg->entries)[0]->get_value("quotaDeviceParameters"),
    };
  } else {
    die "This computer ($ip) is not configured in LDAP to run quota (missing service quotaService).";
  }

  return $client_settings;
}

END {}

1;

__END__
