#######################################################################
#
# Argonaut::Common package -- Argonaut basic functions.
#
# Copyright (c) 2008 Landeshauptstadt München
# Copyright (C) 2011 FusionDirectory project
#
# Author: Matthias S. Benkmann
#         Come Bernigaud
#         Benoit Mortier
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

package Argonaut::Common;

use strict;
use warnings;

use 5.008;

use Net::LDAP;
use Net::LDAP::Constant qw(LDAP_NO_SUCH_OBJECT LDAP_REFERRAL);
use URI;
use File::Path;

my $iptool = "ifconfig";

BEGIN
{
  use Exporter ();
  use vars qw(%EXPORT_TAGS @ISA $VERSION);
  $VERSION = '2011-04-11';
  @ISA = qw(Exporter);

  %EXPORT_TAGS = (
    'ldap' => [qw(
      &argonaut_ldap_parse_config
      &argonaut_ldap_parse_config_ex
      &argonaut_ldap_parse_config_multi
      &argonaut_ldap_fsearch
      &argonaut_ldap_rsearch
      &argonaut_ldap_is_single_result
      &argonaut_ldap_split_dn
      &argonaut_ldap_init
      &argonaut_get_generic_settings
      &argonaut_get_client_settings
      &argonaut_get_server_settings
      &argonaut_get_crawler_settings
      &argonaut_get_ldap2repository_settings
      &argonaut_get_ldap2zone_settings
      &argonaut_get_fuse_settings
    )],
    'file' => [qw(
      &argonaut_file_write
      &argonaut_file_chown
      &argonaut_options_parse
      &argonaut_get_mac_pxe
      &argonaut_create_dir
    )],
    'array' => [qw(
      &argonaut_array_find_and_remove
    )],
    'string' => [qw(
      &argonaut_gen_random_str
    )],
     'net' => [qw(
      &argonaut_get_mac
    )]
  );

  Exporter::export_ok_tags(keys %EXPORT_TAGS);
}

#-----------------------------------------------------------------------------
# routine to get mac from a defined interface
#
# $interface     = name of the interface
#
# Returns the mac of the interface
#
sub argonaut_get_mac {
    my ($interface) = @_;

    my $mac = `LANG=C $iptool $interface | awk '/$interface/{ print \$5 }'`;
    chomp ($mac);

    return $mac;
}

#-----------------------------------------------------------------------------
# routine to get mac from a pxe file
#
# $filename     = name of the pxe file
#
# Returns the mac of the interface
#
sub argonaut_get_mac_pxe {
  my ($filename) = @_;

  my $mac = $filename;
  $mac =~ tr/-/:/;
  $mac = substr( $mac, -1*(5*3+2) );
  chomp ($mac);

  return $mac;
}

#------------------------------------------------------------------------------
# Common LDAP initialization routine
#
# $ldap_conf      = LDAP config file - may be undef
# $prompt_dn      = Prompt user for bind dn if true
# $bind_dn        = Use DN to bind to LDAP server
# $prompt_pwd     = Prompt user for bind password if true
# $bind_pwd       = Use password to bind to LDAP server
# $obfuscate_pwd  = Show stars instead omiting echo
#
# Returns a hash of results
#  'BASE'    => LDAP search base from config
#  'URIS'    => LDAP server URIs from config
#  'HANDLE'  => Net::LDAP handle
#  'BINDDN'  => Bind DN from config or prompt
#  'BINDPWD' => Bind password from prompt
#  'BINDMSG' => Bind result messages
#  'CFGFILE' => Config file used
#  'ERROR'   => Error Number
#  'ERRORMSG' => Error Message
#
# These values are just filled, if they weren't provided,
# i.e.
#
sub argonaut_ldap_init {
  my( $ldap_conf, $prompt_dn, $bind_dn,
      $prompt_pwd, $bind_pwd, $obfuscate_pwd ) = @_;
  my %results;

  # Parse ldap config
  my ($base,$ldapuris) = argonaut_ldap_parse_config( $ldap_conf );
  %results = ( 'BASE' => $base, 'URIS' => $ldapuris);

  if ( ! defined $base ) {
    %results = ( 'ERROR' => 1, 'ERRORMSG' => "Couldn't find LDAP base in config!");
    return \%results;
  }

  if ( ! defined $ldapuris ) {
    %results = ( 'ERROR' => 1, 'ERRORMSG' => "Couldn't find LDAP URI in config!");
    return \%results;
  }

  my $ldap = Net::LDAP->new( $ldapuris );

  if ( ! defined $ldap ) {
    %results = ( 'ERROR' => 1, 'ERRORMSG' => "LDAP 'new' error: '$@' with parameters '".join(",",@{$ldapuris})."'");
    return \%results;
  }

  $results{ 'HANDLE' } = $ldap;

  # Prompt for DN
  if( (! defined $bind_dn) && (defined $prompt_dn && $prompt_dn) )
  {
    $| = 1;
    print( 'Bind DN: ' );
    $| = 0;
    $bind_dn = <STDIN>;
    $results{ 'BINDDN' } = $bind_dn;
  }

  my $mesg;
  if( defined $bind_dn ) {
    if( defined $bind_pwd ) {
      $mesg = $ldap->bind( $bind_dn, password => $bind_pwd );
    }
    elsif( defined $prompt_pwd && $prompt_pwd) {
      # Prompt for password

      $| = 1;
      print( 'Password: ' );
      $| = 0;
      $bind_pwd = '';

      # Disable terminal echo
      system "stty -echo -icanon";

      my $inchr;
      while (sysread STDIN, $inchr, 1) {
        if (ord($inchr) < 32) { last; }
        $bind_pwd .= $inchr;
        syswrite( STDOUT, "*", 1 ) # print asterisk instead
          if( defined $obfuscate_pwd && $obfuscate_pwd );
      }
      system "stty echo icanon";

      $results{ 'BINDPWD' } = $bind_pwd;

      $mesg = $ldap->bind( $bind_dn, password => $bind_pwd );
    }
    else { $mesg = $ldap->bind( $bind_dn ); }
  }
  else {
         $mesg = $ldap->bind();
         $results{ 'BINDMSG' } = $mesg;
       } # Anonymous bind

  if ( $mesg->code != 0 ) {
    %results = ( 'ERROR' => 1, 'ERRORMSG' => "LDAP bind error: " . $mesg->error . "(" . $mesg->code . ")");
    return \%results;
  }

  $results{ 'ERROR' } = 0;

  return \%results;
}

#------------------------------------------------------------------------------
sub argonaut_ldap_parse_config
{
  my ($ldap_config) = @_;

  # Try to guess the location of the ldap.conf - file
  $ldap_config = $ENV{ 'LDAPCONF' }
    if (!defined $ldap_config && exists $ENV{ 'LDAPCONF' });
  $ldap_config = "/etc/ldap/ldap.conf"
    if (!defined $ldap_config);
  $ldap_config = "/etc/openldap/ldap.conf"
    if (!defined $ldap_config);
  $ldap_config = "/etc/ldap.conf"
    if (!defined $ldap_config);

  # Read LDAP
  return if( ! open (LDAPCONF,"${ldap_config}") );

  my @content=<LDAPCONF>;
  close(LDAPCONF);

  my ($ldap_base, @ldap_uris);
  # Scan LDAP config
  foreach my $line (@content) {
    $line =~ /^\s*(#|$)/ && next;
    chomp($line);

    if ($line =~ /^BASE\s+(.*)$/i) {
      $ldap_base= $1;
      next;
    }
    if ($line =~ /^URI\s+(.*)\s*$/i) {
      my (@ldap_servers) = split( ' ', $1 );
      foreach my $server (@ldap_servers) {
        if ( $server =~ /^((ldap[si]?:\/\/)([^\/:\s]+)?(:([0-9]+))?\/?)$/ ) {
          my $ldap_server = $3 ? $1 : $2.'localhost';
          $ldap_server =~ s/\/\/127\.0\.0\.1/\/\/localhost/;
          push @ldap_uris, $ldap_server
          if ( ! grep { $_ =~ /^$ldap_server$/ } @ldap_uris );
        }
      }
      next;
    }
  }

  return( $ldap_base, \@ldap_uris );
}

#------------------------------------------------------------------------------
sub argonaut_ldap_parse_config_ex
{
  my %result = ();

  my $ldap_info = '/etc/ldap/ldap-shell.conf';
  if ( -r '/etc/ldap/ldap-offline.conf' ) {
    $ldap_info = '/etc/ldap/ldap-offline.conf';
  }

  if (!open( LDAPINFO, "<${ldap_info}" ))
  {
     warn "Couldn't open ldap info ($ldap_info): $!\n";
     return undef;
  }
  while( <LDAPINFO> ) {
    if( $_ =~ m/^([a-zA-Z_0-9]+)="(.*)"$/ ) {
      if ($1 eq "LDAP_URIS") {
        my @uris = split(/ /,$2);
        $result{$1} = \@uris;
      }
      else {
        $result{$1} = $2;
      }
    }
  }
  close( LDAPINFO );
  if (not exists($result{"LDAP_URIS"}))
  {
    warn "LDAP_URIS missing in file $ldap_info\n";
  }
  return \%result;
}

# Split the dn (works with escaped commas)
sub argonaut_ldap_split_dn {
  my ($dn) = @_;

  # Split at comma
  my @comma_rdns = split( ',', $dn );
  my @result_rdns = ();
  my $line = '';

  foreach my $rdn (@comma_rdns) {
    # Append comma and rdn to line
    if( '' eq $line ) { $line = $rdn; }
    else { $line .= ',' . $rdn; }

    # Count the backslashes at the end. If we have even length
    # of $bs add to result array and set empty line
    my($bs) = $rdn =~ m/([\\]+)$/;
    $bs = "" if( ! defined $bs );
    if( 0 == (length($bs) % 2) ) {
      push( @result_rdns, $line );
      $line = "";
    }
  }

  return @result_rdns;
}

#------------------------------------------------------------------------------
#
# parse config for user or global config
#
sub argonaut_ldap_parse_config_multi
{
  my ($ldap_config) = @_;

  # Indicate, if it's a user or global config
  my $is_user_cfg = 1;

  # If we don't get a config, go searching for it
  if( ! defined $ldap_config ) {

    # Check the local and users LDAP config name
    my $ldaprc = ( exists $ENV{ 'LDAPRC' } )
               ? basename( $ENV{ 'LDAPRC' } ) : 'ldaprc';

    # First check current directory
    $ldap_config = $ENV{ 'PWD' } . '/' . $ldaprc;
    goto config_open if( -e $ldap_config );

    # Second - visible in users home
    $ldap_config = $ENV{ 'HOME' } . '/' . $ldaprc;
    goto config_open if( -e $ldap_config );

    # Third - hidden in users home
    $ldap_config = $ENV{ 'HOME' } . '/.' . $ldaprc;
    goto config_open if( -e $ldap_config );

    # We don't allow BINDDN in global config
    $is_user_cfg = 0;

    # Global environment config
    if( exists $ENV{ 'LDAPCONF' } ) {
      $ldap_config = $ENV{ 'LDAPCONF' };
      goto config_open if( -e $ldap_config );
    }

    # Last chance - global config
    $ldap_config = '/etc/ldap/ldap.conf'
  }

config_open:
  # Read LDAP file if it's < 100kB
  return if( (-s "${ldap_config}" > 100 * 1024)
          || (! open( LDAPCONF, "<${ldap_config}" )) );

  my @content = <LDAPCONF>;
  close( LDAPCONF );

  my( $ldap_base, @ldap_uris, $ldap_bind_dn );

  # Parse LDAP config
  foreach my $line (@content) {
    $line =~ /^\s*(#|$)/ && next;
    chomp($line);

    if ($line =~ /^BASE\s+(.*)$/i) {
      $ldap_base= $1;
    }
    elsif( $line =~ /^BINDDN\s+(.*)$/i ) {
      $ldap_bind_dn = $1 if( $is_user_cfg );
    }
    elsif ($line =~ m#^URI\s+(.*)\s*$#i ) {
      my (@ldap_servers) = split( ' ', $1 );
      foreach my $server (@ldap_servers) {
        push( @ldap_uris, $1 )
          if( $server =~ m#^(ldaps?://([^/:\s]+)(:([0-9]+))?)/?$#i );
      }
    }
  }

  return( $ldap_base, \@ldap_uris, $ldap_bind_dn, $ldap_config );
}

#------------------------------------------------------------------------------
#
sub argonaut_file_write {

  my @opts = @_;
  my $len = scalar @_;
  ($len < 2) && return;

  my $filename = shift;
  my $data = shift;

  open (SCRIPT,">${filename}") || warn "Can't create ${filename}. $!\n";
  print SCRIPT $data;
  close(SCRIPT);

  ($opts[2] ne "") && chmod oct($opts[2]),${filename};
  ($opts[3] ne "") && argonaut_file_chown(${filename}, $opts[3]);
}

#------------------------------------------------------------------------------
#
sub argonaut_file_chown
{
  my @owner = split('.',$_[1]);
  my $filename = $_[0];
  my ($uid,$gid);
  $uid = getpwnam($owner[0]);
  $gid = getgrnam($owner[1]);

  chown $uid, $gid, $filename;
}

=item argonaut_create_dir
Create a directory
=cut
sub argonaut_create_dir
{
  my ($dir) = @_;

  mkdir($dir,755);
}
#------------------------------------------------------------------------------
#
# Common checks for forward and reverse searches
#
sub argonaut_ldap_search_checks {
  my( $base, $sbase ) = (@_)[1,2];

  if( scalar @_ < 3 ) {
    warn( "argonaut_ldap_search needs at least 3 parameters" );
    return;
  };

  if( defined $sbase && (length($sbase) > 0) ) {
    # Check, if $sbase is a base of $base
    if( $sbase ne substr($base,-1 * length($sbase)) ) {
      warn( "argonaut_ldap_search: (1) '$sbase' isn't the base of '$base'" );
      return;
    }

    $base = substr( $base, 0, length( $base ) - length( $sbase ) );

    # Check, if $base ends with ',' after $sbase strip
    if( ',' ne substr( $base, -1 ) ) {
      warn( "argonaut_ldap_search: (2) '$sbase' isn't the base of '$base'" );
      return;
    }
    $base  = substr( $base, 0, length($base) - 1 );
    $sbase = ',' . $sbase;
  }
  else { $sbase = ''; }

  return( $base, $sbase );
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $ldap    = Net::LDAP handle
# $base    = Search base ( i.e.: ou=test,ou=me,ou=very,ou=well )
# $sbase   = Stop base ( i.e.: ou=very,ou=well )
# $filter  = LDAP filter
# $scope   = LDAP scope
# $subbase = On every $base look into $subbase,$base ( i.e.: ou=do )
# $attrs   = Result attributes
#
# Example searches in:
#   ou=do,ou=test,ou=me,ou=very,ou=well
#   ou=do,ou=me,ou=very,ou=well
#   ou=do,ou=very,ou=well
#
# Returns (Net::LDAP::Search, $search_base) on LDAP failure
# Returns (Net::LDAP::Search, $search_base) on success
# Returns undef on non-LDAP failures
#
sub argonaut_ldap_rsearch {
  use Switch;

  my ($ldap,$base,$sbase,$filter,$scope,$subbase,$attrs) = @_;

  ( $base, $sbase ) = argonaut_ldap_search_checks( @_ );
  return if( ! defined $base );

  my (@rdns,$search_base,$mesg);

  @rdns = argonaut_ldap_split_dn( $base );
  return if( 0 == scalar @rdns );

  while( 1 ) {

    # Walk the DN tree
    switch( scalar @rdns ) {
    case 0 {
      # We also want to search the stop base, if it was defined
      return if( ! defined $sbase );
      if( length( $sbase ) > 0 )
        { $search_base = substr( $sbase, 1 ); }
      else { $search_base = ''; }
      undef( $sbase );
      }
    else {
      $search_base = join( ',', @rdns );
      shift(@rdns);
      $search_base .= $sbase;
      }
    }

    # Initialize hash with filter
    my %opts = ( 'filter' => $filter );

    # Set searchbase
    if( defined $subbase && $subbase )
      { $opts{ 'base' } = "${subbase},${search_base}" }
    else { $opts{ 'base' } = "${search_base}" }

    # Set scope
    $opts{ 'scope' } = "$scope" if( defined $scope && $scope );
    $opts{ 'attrs' } = @$attrs if( defined $attrs );

    # LDAP search

    # The referral chasing is much simpler then the OpenLDAP one.
    # It's just single level support, therefore it can't really
    # chase a trail of referrals, but will check a list of them.

    my @referrals;
    my $chase_referrals = 0;
RETRY_SEARCH:
    $mesg = $ldap->search( %opts );

    if( LDAP_REFERRAL == $mesg->code ) { # Follow the referral
      if( ! $chase_referrals ) {
        my @result_referrals = $mesg->referrals();
        foreach my $referral (@result_referrals) {
          my $uri = new URI( $referral );
          next if( $uri->dn ne $opts{ 'base' } ); # But just if we have the same base
          push( @referrals, $uri );
        }
        $chase_referrals = 1;
      }

NEXT_REFERRAL:
      next if( ! length @referrals );
      my $uri = new URI( $referrals[ 0 ] );
      $ldap = new Net::LDAP( $uri->host );
      @referrals = splice( @referrals, 1 );
      goto NEXT_REFERRAL if( ! defined $ldap );
      $mesg = $ldap->bind();
      goto NEXT_REFERRAL if( 0 != $mesg->code );
      goto RETRY_SEARCH;
    }
    if( LDAP_NO_SUCH_OBJECT == $mesg->code ) { # Ignore missing objects (32)
      goto NEXT_REFERRAL if( scalar @referrals );
      next;
    }

    return $mesg if( $mesg->code ); # Return undef on other failures

    last if( $mesg->count() > 0 );
  }

  return( $mesg, ${search_base} );
}

#------------------------------------------------------------------------------
# See argonaut_ldap_fsearch
#
# sbase = start base
#
# Example searches in:
#   ou=do,ou=very,ou=well
#   ou=do,ou=me,ou=very,ou=well
#   ou=do,ou=test,ou=me,ou=very,ou=well
#
sub argonaut_ldap_fsearch {
  use Switch;

  my ($ldap,$base,$sbase,$filter,$scope,$subbase,$attrs) = @_;

  ( $base, $sbase ) = argonaut_ldap_search_checks( @_ );
  return if( ! defined $base );

  my (@rdns,$search_base,$mesg,$rdn_count);

  @rdns = reverse argonaut_ldap_split_dn( $base );
  $rdn_count = scalar @rdns;
  return if( 0 == $rdn_count );

  while( 1 ) {

    # Walk the DN tree
    if( ! defined $search_base ) {
      # We need to strip the leading ",", which is needed for research
      if( length( $sbase ) > 0 )
        { $search_base = substr( $sbase, 1 ); }
      else { $search_base = ''; }
    }
    elsif( 0 == scalar @rdns ) {
      return undef;
    }
    else {
      $search_base = $rdns[ 0 ] . ',' . $search_base;
      shift(@rdns);
    }

    # Initialize hash with filter
    my %opts = ( 'filter' => $filter );

    # Set searchbase
    if( defined $subbase && $subbase )
      { $opts{ 'base' } = "${subbase},${search_base}"; }
    else { $opts{ 'base' } = "${search_base}"; }

    # Set scope
    $opts{ 'scope' } = "$scope" if( defined $scope && $scope );
    $opts{ 'attrs' } = @$attrs if( defined $attrs );

    # LDAP search
    $mesg = $ldap->search( %opts );

    next if( $mesg->code == 32 ); # Ignore missing objects (32)
    return $mesg if( $mesg->code ); # Return undef on other failures

    last if( $mesg->count() > 0 );
  }

  return( $mesg, ${search_base} );
}

#------------------------------------------------------------------------------
# generic functions for get settings functions
# TODO : add (optional) support for using group config
#
sub argonaut_get_generic_settings {
  my ($objectClass,$params,$ldap_configfile,$ldap_dn,$ldap_password,$ip) = @_;

  my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);

  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my ($ldap,$ldap_base) = ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'});

  my $mesg = $ldap->search( # perform a search
            base   => $ldap_base,
            filter => "(&(objectClass=$objectClass)(ipHostNumber=$ip))",
            attrs => ['macAddress',values(%{$params})]
            );

  if(scalar($mesg->entries)==1) {
    my $settings = {
      'mac'           => ($mesg->entries)[0]->get_value("macAddress")
    };
    while (my ($key,$value) = each(%{$params})) {
      if (($mesg->entries)[0]->get_value("$value")) {
        $settings->{"$key"} = ($mesg->entries)[0]->get_value("$value");
      } else {
        $settings->{"$key"} = "";
      }
    }
    return $settings;
  } elsif(scalar($mesg->entries)==0) {
    die "This computer ($ip) is not configured in LDAP to run this module (missing service $objectClass).";
  } else {
    die "Several computers are associated to IP $ip.";
  }
}

#------------------------------------------------------------------------------
# get server argonaut settings
#
sub argonaut_get_server_settings {
  my ($ldap_configfile,$ldap_dn,$ldap_password,$ip) = @_;
  if ($ip eq "") {
    $ip = "*";
  }
  return argonaut_get_generic_settings(
    'argonautServer',
    {
      'ip'                    => "ipHostNumber",
      'port'                  => "argonautPort",
      'protocol'              => "argonautProtocol",
      'iptool'                => "argonautIpTool",
      'delete_finished_tasks' => "argonautDeleteFinished",
      'interface'             => "argonautWakeOnLanInterface",
      'logdir'                => "argonautLogDir"
    },
    $ldap_configfile,$ldap_dn,$ldap_password,$ip
  );
}

#------------------------------------------------------------------------------
# get client argonaut settings
#
sub argonaut_get_client_settings {
  my ($ldap_configfile,$ldap_dn,$ldap_password,$ip) = @_;

  my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);

  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."\n";
  }

  my ($ldap,$ldap_base) = ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'});

  my $mesg = $ldap->search( # perform a search
            base   => $ldap_base,
            filter => "(&(objectClass=argonautClient)(ipHostNumber=$ip))",
            attrs => [ 'macAddress','argonautClientPort','argonautTaskIdFile',
                       'argonautClientWakeOnLanInterface','argonautClientLogDir' ]
            );

  my $client_settings = {};

  if(scalar($mesg->entries)==1) {
    $client_settings = {
      'ip'          => $ip,
      'mac'         => ($mesg->entries)[0]->get_value("macAddress"),
      'port'        => ($mesg->entries)[0]->get_value("argonautClientPort"),
      'taskidfile'  => ($mesg->entries)[0]->get_value("argonautTaskIdFile"),
      'interface'   => ($mesg->entries)[0]->get_value("argonautClientWakeOnLanInterface"),
      'logdir'      => ($mesg->entries)[0]->get_value("argonautClientLogDir")
    };
  } else {
    $mesg = $ldap->search( # perform a search
              base   => $ldap_base,
              filter => "ipHostNumber=$ip",
              attrs => [ 'dn' ]
              );
    if(scalar($mesg->entries)!=1) {
      die "multiple entries for this IP ($ip)";
    }
    my $dn = ($mesg->entries)[0]->dn();
    $mesg = $ldap->search( # perform a search
          base   => $ldap_base,
          filter => "(&(objectClass=argonautClient)(member=$dn))",
          attrs => [ 'argonautClientPort','argonautTaskIdFile',
                     'argonautClientWakeOnLanInterface','argonautClientLogDir' ]
          );
    if(scalar($mesg->entries)==1) {
      $client_settings = {
        'ip'          => $ip,
        'port'        => ($mesg->entries)[0]->get_value("argonautClientPort"),
        'taskidfile'  => ($mesg->entries)[0]->get_value("argonautTaskIdFile"),
        'interface'   => ($mesg->entries)[0]->get_value("argonautClientWakeOnLanInterface"),
        'logdir'      => ($mesg->entries)[0]->get_value("argonautClientLogDir")
      }; # FIXME : when in a group, not returning macAddress
    } else {
      die "This computer ($ip) is not configured in LDAP to run an argonaut client.";
    }
  }

  return $client_settings;
}

#------------------------------------------------------------------------------
# get ldap2repository argonaut settings
#
sub argonaut_get_ldap2repository_settings {
  return argonaut_get_generic_settings(
    'argonautMirrorConfig',
    {
      'mirrordir'       => 'argonautMirrorDir',
      'errors'          => 'argonautLdap2repErrors',
      'source'          => 'argonautLdap2repSource',
      'gpgcheck'        => 'argonautLdap2repGPGCheck',
      'contents'        => 'argonautLdap2repContents',
      'verbose'         => 'argonautLdap2repVerbose',
    },
    @_
  );
}

#------------------------------------------------------------------------------
# get crawler argonaut settings
#
sub argonaut_get_crawler_settings {
  return argonaut_get_generic_settings(
    'argonautMirrorConfig',
    {
      'mirrordir'       => 'argonautMirrorDir',
      'packagesfolder'  => 'argonautCrawlerPackagesFolder',
    },
    @_
  );
}

#------------------------------------------------------------------------------
# get ldap2zone settings
#
sub argonaut_get_ldap2zone_settings {
  return argonaut_get_generic_settings(
    'argonautDNSConfig',
    {
      'binddir'       => 'argonautLdap2zoneBindDir',
      'allownotify'   => 'argonautLdap2zoneAllowNotify',
      'allowupdate'   => 'argonautLdap2zoneAllowUpdate',
      'allowtransfer' => 'argonautLdap2zoneAllowTransfer',
      'ttl'           => 'argonautLdap2zoneTTL',
      'rndc'          => 'argonautLdap2zoneRndc',
    },
    @_
  );
}

#------------------------------------------------------------------------------
# get fuse settings
#
sub argonaut_get_fuse_settings {
  return argonaut_get_generic_settings(
    'argonautFuseConfig',
    {
      'default_mode'        => 'argonautFuseDefaultMode',
      'logdir'              => 'argonautFuseLogDir',
      'pxelinux_cfg'        => 'argonautFusePxelinuxCfg',
      'pxelinux_cfg_static' => 'argonautFusePxelinuxCfgStatic',
    },
    @_
  );
}

#------------------------------------------------------------------------------
#
# $search_result = Net::LDAP::Serach
# $get_entry     = boolean
#
# if $get_entry == true,  return $entry
#               == false, return 1
#
# returns 0 on failure
#
sub argonaut_ldap_is_single_result {
  my ($search_result,$get_entry) = @_;
  my $result = 0;
  if( (defined $search_result)
      && (0 == $search_result->code)
      && (1 == $search_result->count()) )
  {
    if( defined $get_entry && $get_entry )
      { $result = ($search_result->entries())[ 0 ]; }
    else { $result = 1; }
  }
  return $result;
}


#------------------------------------------------------------------------------
#
sub argonaut_array_find_and_remove {
  my ($haystack,$needle) = @_;
  my $index = 0;

  foreach my $item (@$haystack) {
    if ($item eq $needle) {
      splice( @$haystack, $index, 1 );
      return 1;
    }
    $index++;
  }
  return 0;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Generate a random string based on a symbolset
#
# @param int $strlen: length of result string
# @param array ref: symbol set (optional)
# @return string or undef
#
sub argonaut_gen_random_str {
  my ($strlen, $symbolset) = @_;
  return if( (! defined $strlen) || (0 > $strlen) );
  return '' if( 0 == $strlen );
  if( (! defined $symbolset)
    || ('ARRAY' ne ref( $symbolset ))
    || (0 >= scalar( @$symbolset )) )
  {
    my @stdset = (0..9, 'a'..'z', 'A'..'Z');
    $symbolset = \@stdset;
  }

  my $randstr = join '',
    map @$symbolset[rand @$symbolset], 0..($strlen-1);
  return $randstr;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Parse options from array into hash
#
# Copied from Net::LDAP
#
sub argonaut_options_parse {
  my %ret = @_;
  my $once = 0;
  for my $v (grep { /^-/ } keys %ret) {
    require Carp;
    $once++ or Carp::carp("deprecated use of leading - for options");
    $ret{substr($v,1)} = $ret{$v};
  }

  $ret{control} = [ map { (ref($_) =~ /[^A-Z]/) ? $_->to_asn : $_ }
                      ref($ret{control}) eq 'ARRAY'
                        ? @{$ret{control}}
                        : $ret{control}
                  ]
    if exists $ret{control};

  \%ret;
}

END {}

1;

__END__

=head1 NAME

Argonaut::Common - Argonaut basic functions

=head1 SYNOPSIS

use Argonaut::Utils;

  $result = process_input($line);

=head1 Function C<process_input>

=head2 Syntax

  $result = process_input($line);

=head2 Arguments

C<$line> input line we get

=head2 Return value

 true if stream wants us to finish

=head2 Description

C<process_input> parses information from the lines and sets the progress respectively

=head1 BUGS

Please report any bugs, or post any suggestions, to the fusiondirectory mailing list fusiondirectory-users or to
<https://forge.fusiondirectory.org/projects/argonaut-agents/issues/new>

=head1 LICENCE AND COPYRIGHT

This code is part of FusionDirectory <http://www.fusiondirectory.org>

=over 3

=item Copyright (C) 2008 Landeshauptstadt München

=item Copyright (C) 2011 FusionDirectory project

=back

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut


# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
