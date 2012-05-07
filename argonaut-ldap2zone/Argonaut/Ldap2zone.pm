#######################################################################
#
# Argonaut::Ldap2zone -- create zone files from LDAP DNS zones
#
# Copyright (C) 2012 FusionDirectory project <contact@fusiondirectory.org>
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

package Argonaut::Ldap2zone;

use Exporter 'import';              # gives you Exporter's import() method directly
@EXPORT_OK = qw(&argonaut_ldap2zone);  # symbols to export on request

use strict;
use warnings;

use 5.008;

use Config::IniFiles;
use DNS::ZoneParse;

use Argonaut::Common qw(:ldap);

my $configfile = "/etc/argonaut/argonaut.conf";
my @record_types = ('a','cname','mx','ns','ptr','txt');#,'srv','hinfo','rp','loc'

my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

=item argonaut_ldap2zone
Write a zone file for the LDAP zone and its reverse, generate named.conf files and assure they are included
Params : zone name, verbose flag
=cut
sub argonaut_ldap2zone
{
  my($zone,$verbose) = @_;
  
  my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

  my $client_ip               =   $config->val( client => "client_ip" ,"");
  my $ldap_configfile         =   $config->val( ldap => "config"      ,"/etc/ldap/ldap.conf");
  my $ldap_dn                 =   $config->val( ldap => "dn"          ,"");
  my $ldap_password           =   $config->val( ldap => "password"    ,"");

  my $settings = argonaut_get_ldap2zone_settings($ldap_configfile,$ldap_dn,$ldap_password,$client_ip);

  my $BIND_DIR                =   $settings->{'binddir'};
  my $ALLOW_NOTIFY            =   $settings->{'allownotify'};
  my $ALLOW_UPDATE            =   $settings->{'allowupdate'};
  my $ALLOW_TRANSFER          =   $settings->{'allowtransfer'};
  my $TTL                     =   $settings->{'ttl'};
  my $RNDC                    =   $settings->{'rndc'};

  if(not -d $BIND_DIR) {
    die "$BIND_DIR does not exist";
  }
  
  if($ALLOW_NOTIFY eq "FALSE") {
    $ALLOW_NOTIFY = "";
  }

  if (substr($zone,-1) ne ".") { # If the end point is not there, add it
    $zone = $zone.".";
  }

  print "Searching DNS Zone '$zone'\n" if $verbose;

  my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);
    
  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my ($ldap,$ldap_base) = ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'});

  my $dn = zoneparse($ldap,$ldap_base,$zone,$BIND_DIR,$TTL,$verbose);

  my $reverse_zone = get_reverse_zone($ldap,$ldap_base,$dn);
  print "Reverse zone is $reverse_zone\n" if $verbose;

  zoneparse($ldap,$ldap_base,$reverse_zone,$BIND_DIR,$TTL,$verbose);
    
  create_namedconf($zone,$reverse_zone,$BIND_DIR,$ALLOW_NOTIFY,$ALLOW_UPDATE,$ALLOW_TRANSFER);
  
  system("$RNDC reconfig && $RNDC freeze && $RNDC reload && $RNDC thaw");
}
  
=item zoneparse
Create a Zone file for a zone taken from the LDAP
Params : ldap handle, ldap base, zone name, bind dir, TTL, verbose flag
Returns : dn of the zone
=cut
sub zoneparse
{
  my ($ldap,$ldap_base,$zone,$BIND_DIR,$TTL,$verbose) = @_;
  my $mesg = $ldap->search( # perform a search
          base   => $ldap_base,
          filter => "zoneName=$zone",
          #~ attrs => [ 'ipHostNumber' ]
          );
          
  $mesg->code && die "Error while searching DNS Zone '$zone' :".$mesg->error;

  print "Found ".scalar($mesg->entries())." results\n" if $verbose;

  my $zonefile = DNS::ZoneParse->new();

  my $records = {};
  foreach my $record (@record_types) {
    $records->{$record} = $zonefile->$record();
  }

  my $dn; # Dn of zone entry;

  foreach my $entry ($mesg->entries()) {
    my $name = $entry->get_value("relativeDomainName");
    if(!$name) { print "no name\n"; next; }
    my $class = $entry->get_value("dnsClass");
    if(!$class) { print "no class\n"; next; }
    my $ttl = $entry->get_value("dNSTTL");
    if(!$ttl) {
      $ttl = "";#$default_ttl;
    }
    while(my ($type,$list) = each %{$records}){
      my $value = $entry->get_value($type."Record");
      if($value) {
        if($name ne "@") {
          push @{$list},{ name => $name, class => $class,
                          host => $value, ttl => $ttl };
        } else {
          push @{$list},{ host => $value, ttl => $ttl };
        }
        print "Added record $type $name $class $value $ttl\n" if $verbose;
        last;
      }
    }
    my $soa = $entry->get_value("soaRecord");
    if($soa) {
      my $soa_record = $zonefile->soa();
      my (@soa_fields) = split(' ',$soa);
      $soa_record->{'primary'}  = $soa_fields[0];
      $soa_record->{'email'}    = $soa_fields[1];
      $soa_record->{'serial'}   = $soa_fields[2];
      $soa_record->{'refresh'}  = $soa_fields[3];
      $soa_record->{'retry'}    = $soa_fields[4];
      $soa_record->{'expire'}   = $soa_fields[5];
      $soa_record->{'minimumTTL'}  = $soa_fields[6];
      
      $soa_record->{'class'}    = $class;
      $soa_record->{'ttl'}      = $TTL;
      $soa_record->{'origin'}   = $name;
      print "Added record SOA $name $class $soa $TTL\n" if $verbose;
      $dn = $entry->dn();
    }
  }
  
  # write the new zone file to disk 
  my $file_output = "$BIND_DIR/db.$zone";
  my $newzone;
  open($newzone, '>', $file_output) or die "error while trying to open $file_output";
  print $newzone $zonefile->output();
  close $newzone;
  
  return $dn;
}

=item get_reverse_zone
Params : ldap handle, ldap base, zone dn
Returns : reverse zone name
=cut
sub get_reverse_zone
{
  my($ldap,$ldap_base,$zone_dn) = @_;
  my $mesg = $ldap->search( # Searching reverse zone name
          base   => $zone_dn,
          filter => "zoneName=*",
          scope => 'one',
          attrs => [ 'zoneName' ]
          );
          
  $mesg->code && die "Error while searching DNS reverse zone :".$mesg->error;

  die "Error : found ".scalar($mesg->entries())." results for reverse DNS zone\n" if (scalar($mesg->entries()) != 1);

  return ($mesg->entries)[0]->get_value("zoneName");
}

=item create_namedconf
Create file $BIND_DIR/named.conf.ldap2zone
Params : zone name, reverse zone name
Returns : 
=cut
sub create_namedconf
{
  my($zone,$reverse_zone,$BIND_DIR,$ALLOW_NOTIFY,$ALLOW_UPDATE,$ALLOW_TRANSFER) = @_;

  if($ALLOW_NOTIFY) {
    $ALLOW_NOTIFY = "notify yes;";
  } else {
    $ALLOW_NOTIFY = "";
  }

  if ($ALLOW_UPDATE) {
    $ALLOW_UPDATE = "allow-update {$ALLOW_UPDATE};";
  } else {
    $ALLOW_UPDATE = "";
  }

  if ($ALLOW_TRANSFER) {
    $ALLOW_TRANSFER = "allow-transfer {$ALLOW_TRANSFER};";
  } else {
    $ALLOW_TRANSFER = "";
  }
  
  my $namedfile;
  open($namedfile, '>', "$BIND_DIR/named.conf.ldap2zone.$zone") or die "error while trying to open $BIND_DIR/named.conf.ldap2zone.$zone";
  print $namedfile <<EOF;
zone "$zone" {
  type master;
  $ALLOW_NOTIFY
  file "$BIND_DIR/db.$zone";
  $ALLOW_UPDATE
  $ALLOW_TRANSFER
};
zone "$reverse_zone" {
  type master;
  $ALLOW_NOTIFY
  file "$BIND_DIR/db.$reverse_zone";
  $ALLOW_UPDATE
  $ALLOW_TRANSFER
};
EOF
  close $namedfile;
  
  open($namedfile, '>', "$BIND_DIR/named.conf.ldap2zone") or die "error while trying to open $BIND_DIR/named.conf.ldap2zone";
  opendir DIR, $BIND_DIR or die "Error while openning $BIND_DIR!";
  my @files = readdir DIR;
  foreach my $file (grep { /^named\.conf\.ldap2zone\./ } @files) {
    print $namedfile qq{include "$BIND_DIR/$file";\n};
  }
  close $namedfile;
}

1;

__END__
