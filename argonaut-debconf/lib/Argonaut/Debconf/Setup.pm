package Argonaut::Debconf::Setup;

=head1 DESCRIPTION

Config object for the Debconf plugin.

All the config values are currently defined here
and there's no external config file.

=cut

use warnings;
use strict;
use base qw/Exporter/;
our @EXPORT_OK= qw/%config/;

use Config::IniFiles;
use Argonaut::Common qw(:ldap);

my $configfile = "/etc/argonaut/argonaut.conf";
my $confighash = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

my $client_ip                       =   $confighash->val( client => "client_ip" ,"");
my $ldap_configfile                 =   $confighash->val( ldap => "config"      ,"/etc/ldap/ldap.conf");
my $ldap_dn                         =   $confighash->val( ldap => "dn"          ,"");
my $ldap_password                   =   $confighash->val( ldap => "password"    ,"");

my ($base,$ldapuris) = argonaut_ldap_parse_config( $ldap_configfile );

our %config= (
  ldap_host           => $ldapuris,
  ldap_base           => $base,
  ldap_systems_base   => 'ou=systems,'.$base,

  ldap_config         => $ldap_configfile,
  ldap_binddn         => $ldap_dn,
  ldap_bindpw         => $ldap_password,

  ldap_scheme         => 'ldap', # ldaps, ldapi
  ldap_timeout        => 120,
  ldap_protocol       => 3,
  ldap_onerror        => 'warn', # die, warn, undef, sub{}
  ldap_raw            => qr/(?i:^jpegPhoto|;binary)/,

  debconf_rdn         => 'ou=debconf',
  questions_rdn       => 'ou=questions',
  templates_rdn       => 'ou=templates',

  seeAlso             => 1,

  preseed_cgi         => {
    flag              => 'preseed',
    debug             => 0,
    must_exist        => 1,
  },

  pxelinux_cfg        => {
    debug             => 1,
    dynamic           => 1,
    mount_point       => '/srv/tftp/pxelinux.cfg',
  },
);

1

__END__
=head1 REFERENCES

=head1 AUTHORS

SPINLOCK - Advanced GNU/Linux networks in commercial and education sectors.

Copyright (C) 2011, Davor Ocelic <docelic@spinlocksolutions.com>
Copyright (C) 2011-2013 FusionDirectory project

Copyright 2011, SPINLOCK Solutions,
  http://www.spinlocksolutions.com/,
  http://techpubs.spinlocksolutions.com/

=head1 LICENSE

GNU GPL v3 or later. http://www.gnu.org/licenses/gpl.html

=cut
