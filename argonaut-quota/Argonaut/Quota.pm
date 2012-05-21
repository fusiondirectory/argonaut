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

use Quota;

use Argonaut::Common qw(:ldap);

BEGIN
{
  use Exporter ();
  use vars qw(@EXPORT_OK @ISA $VERSION);
  $VERSION = '2012-04-24';
  @ISA = qw(Exporter);

  @EXPORT_OK = qw(write_warnquota_file write_quotatab_file get_quota_settings apply_quotas);
}

=head1
Warnquota

Write warnquota and quotatab files
=cut
sub write_warnquota_file {
  my ($settings,$warnquota_file) = @_;

  open (WARNQUOTA, ">", $warnquota_file) or die "Could not open file $warnquota_file";

  # edition of warnquota.conf
  print WARNQUOTA "MAIL_CMD               = ".$settings->{'mail_cmd'}."\n";
  print WARNQUOTA "CC_TO                  = ".$settings->{'cc_to'}."\n";
  print WARNQUOTA "FROM                   = ".$settings->{'from'}."\n";
  print WARNQUOTA "SUBJECT                = ".$settings->{'subject'}."\n";
  # Support email for assistance (included in generated mail)
  print WARNQUOTA "SUPPORT                = ".$settings->{'support'}."\n";
  # Support phone for assistance (included in generated mail)
  # The message to send
  print WARNQUOTA "MESSAGE                = ".$settings->{'message'}."\n";
  # The signature of the mail
  print WARNQUOTA "SIGNATURE              = ".$settings->{'signature'}."\n";
  # character set the email is to be send in
  print WARNQUOTA "CHARSET                = ".$settings->{'charset'}."\n";
  # add LDAP support
  print WARNQUOTA "LDAP_MAIL              = true"."\n";
  print WARNQUOTA "LDAP_SEARCH_ATTRIBUTE  = ".$settings->{'ldap_searchattribute'}."\n";
  print WARNQUOTA "LDAP_MAIL_ATTRIBUTE    = mail\n";
  print WARNQUOTA "LDAP_BASEDN            = ".$settings->{'ldap_basedn'}."\n";
  print WARNQUOTA "LDAP_HOST              = ".$settings->{'ldap_host'}."\n";
  print WARNQUOTA "LDAP_PORT              = ".$settings->{'ldap_port'}."\n";
  print WARNQUOTA "LDAP_USER_DN           = ".$settings->{'ldap_userdn'}."\n";
  print WARNQUOTA "LDAP_PASSWORD          = ".$settings->{'ldap_userpwd'}."\n";
  # end of warnquota.conf
}

sub write_quotatab_file {
  my ($settings,$quotatab_file) = @_;

  open (QUOTATAB, ">", $quotatab_file) or die "Could not open file $quotatab_file";

  # Begin of quota tab edition
  my @quotaDeviceParameters = @{$settings->{'device_parameters'}};
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
            attrs => [  'cn','quotaDeviceParameters',
                        'quotaLdapSearchIdAttribute',
                        'quotaLdapServerURI','quotaLdapServerUserDn',
                        'quotaLdapServerUserPassword','quotaMsgCharsetSupport',
                        'quotaMsgContactSupport','quotaMsgContentSupport',
                        'quotaMsgFromSupport','quotaMsgSignatureSupport',
                        'quotaMsgSubjectSupport','quotaMailCommand',
                        'quotaCarbonCopyMail' ]
            );

  my $settings = {};

  if(scalar($mesg->entries)==1) {
    my $uri = URI->new(($mesg->entries)[0]->get_value('quotaLdapServerURI'));

    $settings = {
      'hostname'              => ($mesg->entries)[0]->get_value("cn"),
      'ldap_basedn'           => $uri->dn,
      'ldap_host'             => $uri->host,
      'ldap_port'             => $uri->port,
    };
    my %keys = (
      'mail_cmd'              => "quotaMailCommand",
      'cc_to'                 => "quotaCarbonCopyMail",
      'from'                  => "quotaMsgFromSupport",
      'subject'               => "quotaMsgSubjectSupport",
      'support'               => "quotaMsgContactSupport",
      'message'               => "quotaMsgContentSupport",
      'signature'             => "quotaMsgSignatureSupport",
      'charset'               => "quotaMsgCharsetSupport",
      'ldap_searchattribute'  => "quotaLdapSearchIdAttribute",
      'ldap_userdn'           => "quotaLdapServerUserDn",
      'ldap_userpwd'          => "quotaLdapServerUserPassword",
    );
    while (my ($key, $value) = each(%keys)) {
      if (($mesg->entries)[0]->get_value($value)) {
        $settings->{$key} = ($mesg->entries)[0]->get_value($value);
      } else {
        $settings->{$key} = "";
      }
    }

    if (($mesg->entries)[0]->get_value('quotaDeviceParameters')) {
      $settings->{'device_parameters'} = ($mesg->entries)[0]->get_value('quotaDeviceParameters', asref=>1);
    } else {
      $settings->{'device_parameters'} = [];
    }
  } else {
    die "This computer ($ip) is not configured in LDAP to run quota (missing service quotaService).";
  }

  return $settings;
}

sub apply_quotas {
  my ($ldap_configfile,$ldap_dn,$ldap_password,$hostname) = @_;

  my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);

  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my ($ldap,$ldap_base) = ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'});

  my $mesg = $ldap->search( # perform a search
            base   => $ldap_base,
            filter => "(objectClass=systemQuotas)",
            attrs => ['quota','uid','uidNumber','gidNumber']
            );

  foreach my $entry ($mesg->entries) {
    my $uid = $entry->get_value("uidNumber");
    my $gid = $entry->get_value("gidNumber");
    my $isUser = (defined $entry->get_value("uid"));
    my @quotas = $entry->get_value("quota");
    foreach my $quota (@quotas) {
      my ($dev,$blocksoft,$blockhard,$inodesoft,$inodehard,$server,$adminlist) = split (':',$quota);
      if ($server eq $hostname) {
        if ($isUser) {
          print "applying quota ($blocksoft, $blockhard, $inodesoft, $inodehard) on $dev for uid $uid\n";
          Quota::setqlim($dev, $uid, $blocksoft,$blockhard, $inodesoft,$inodehard);
        } else {
          print "applying quota ($blocksoft, $blockhard, $inodesoft, $inodehard) on $dev for gid $gid\n";
          Quota::setqlim($dev, $gid, $blocksoft, $blockhard, $inodesoft, $inodehard, 0, 1);
        }
      }
    }
  }
  Quota::sync();
}

END {}

1;

__END__
