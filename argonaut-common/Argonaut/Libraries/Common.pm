#######################################################################
#
# Argonaut::Libraries::Common -- Argonaut basic functions.
#
# Copyright (c) 2008 Landeshauptstadt München
# Copyright (C) 2011-2016 FusionDirectory project
#
# Authors: Matthias S. Benkmann
#         Come Bernigaud
#         Benoit Mortier
#
#  This program is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program; if not, write to the Free Software
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#
#######################################################################

package Argonaut::Libraries::Common;

use strict;
use warnings;

use 5.008;

use JSON::RPC ();
use constant USE_LEGACY_JSON_RPC => ($JSON::RPC::VERSION > 0.96);

use Net::LDAP;
use Net::LDAP::Constant qw(LDAP_NO_SUCH_OBJECT LDAP_REFERRAL);
use URI;
use File::Path;
use Config::IniFiles;
use Digest::SHA;
use MIME::Base64;

my $iptool = "ifconfig";

my $die_endl = "\n"; # Change to "" to have verbose dies

my $configfile = "/etc/argonaut/argonaut.conf";

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
      &argonaut_ldap_branch_exists
      &argonaut_ldap_init
      &argonaut_ldap_handle
      &argonaut_read_ldap_config
      &argonaut_get_generic_settings
      &argonaut_get_client_settings
      &argonaut_get_server_settings
      &argonaut_get_crawler_settings
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
      &argonaut_gen_ssha_token
      &argonaut_check_ssha_token
    )],
     'net' => [qw(
      &argonaut_get_mac
    )],
     'utils' => [qw(
      &argonaut_check_time_frames
    )],
     'config' => [qw(
      &argonaut_read_config
      USE_LEGACY_JSON_RPC
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
      $prompt_pwd, $bind_pwd, $obfuscate_pwd, $ldap_tls ) = @_;
  my %results;

  undef $bind_dn if ($bind_dn eq '');

  # Parse ldap config
  my ($base,$ldapuris,$tlsoptions) = argonaut_ldap_parse_config( $ldap_conf );
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

  if ($ldap_tls) {
    $ldap->start_tls(
      verify      => $tlsoptions->{'REQCERT'},
      clientcert  => $tlsoptions->{'CERT'},
      clientkey   => $tlsoptions->{'KEY'},
      capath      => $tlsoptions->{'CACERTDIR'}
    );
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

sub argonaut_ldap_handle {
  my ($config)  = @_;
  my $ldapinfos = argonaut_ldap_init ($config->{'ldap_configfile'}, 0, $config->{'ldap_dn'}, 0, $config->{'ldap_password'}, 0, $config->{'ldap_tls'});

  if ( $ldapinfos->{'ERROR'} > 0) {
    die $ldapinfos->{'ERRORMSG'}."$die_endl";
  }

  return ($ldapinfos->{'HANDLE'},$ldapinfos->{'BASE'},$ldapinfos);
}

#------------------------------------------------------------------------------
sub argonaut_ldap_parse_config
{
  my ($ldap_config) = @_;
  my $ldapconf;

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
  return if( ! open ($ldapconf,q{<},"${ldap_config}") );

  my @content=<$ldapconf>;
  close($ldapconf);

  my ($ldap_base, @ldap_uris, %tls_options);
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
    if ($line =~ m/^TLS_(REQCERT|CERT|KEY|CACERTDIR)\s+(.*)\s*$/) {
      $tls_options{$1} = $2;
      next;
    }
  }

  return( $ldap_base, \@ldap_uris, \%tls_options);
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

# Check if a designated branch exists
sub argonaut_ldap_branch_exists {
  my ($ldap, $branch) = @_;

  # search for branch
  my $branch_mesg = $ldap->search (base => $branch, filter => '(objectClass=*)', scope => 'base');
  if ($branch_mesg->code == LDAP_NO_SUCH_OBJECT) {
    return 0;
  }
  $branch_mesg->code && die "Error while searching for branch \"$branch\":".$branch_mesg->error;

  my @entries = $branch_mesg->entries;
  return (defined ($entries[0]));
}

#------------------------------------------------------------------------------
#
sub argonaut_file_write {

  my @opts = @_;
  my $len = scalar @_;
  ($len < 2) && return;

  my $filename = shift;
  my $data = shift;
  my $script;

  open ($script,q{>},${filename}) || warn "Can't create ${filename}. $!\n";
  print $script $data;
  close ($script);

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

  mkdir($dir,0755);
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
  my ($ldap,$base,$sbase,$filter,$scope,$subbase,$attrs) = @_;

  ( $base, $sbase ) = argonaut_ldap_search_checks( @_ );
  return if( ! defined $base );

  my (@rdns,$search_base,$mesg);

  @rdns = argonaut_ldap_split_dn( $base );
  return if( 0 == scalar @rdns );

  while( 1 ) {

    # Walk the DN tree
    if (scalar @rdns == 0) {
      # We also want to search the stop base, if it was defined
      return if( ! defined $sbase );
      if( length( $sbase ) > 0 ) {
        $search_base = substr( $sbase, 1 );
      } else {
        $search_base = '';
      }
      undef( $sbase );
    } else {
      $search_base = join( ',', @rdns );
      shift(@rdns);
      $search_base .= $sbase;
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
      next if( ! scalar @referrals );
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
      return;
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

    next if( $mesg->code == LDAP_NO_SUCH_OBJECT ); # Ignore missing objects (32)
    return $mesg if( $mesg->code ); # Return undef on other failures

    last if( $mesg->count() > 0 );
  }

  return( $mesg, ${search_base} );
}

=item trim
trims whitespaces from a given string
=cut
sub trim {
  my $string = shift;
  $string =~ s/^\s+//;
  $string =~ s/\s+$//;
  return $string;
}

#------------------------------------------------------------------------------
# function for reading argonaut config
#
sub argonaut_read_config {
  my %res = ();
  my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

  $res{'server_ip'}       = trim($config->val( server  => "server_ip", ""));
  $res{'client_ip'}       = trim($config->val( client  => "client_ip", ""));
  $res{'ldap_configfile'} = trim($config->val( ldap    => "config",    "/etc/ldap/ldap.conf"));
  $res{'ldap_dn'}         = trim($config->val( ldap    => "dn",        ""));
  $res{'ldap_password'}   = trim($config->val( ldap    => "password",  ""));
  $res{'ldap_tls'}        = trim($config->val( ldap    => "tls",       "off"));

  if ($res{'ldap_tls'} !~ m/^off|on$/i) {
    warn "Unknown value for option ldap/tls: ".$res{'ldap_tls'}." (valid values are on/off)\n";
  }
  $res{'ldap_tls'} = ($res{'ldap_tls'} =~ m/^on$/i);

  return \%res;
}

# Read a config in the LDAP
sub argonaut_read_ldap_config {
  my ($ldap, $ldap_base, $config, $configfilter, $params) = @_;

  my $mesg = $ldap->search (base => $ldap_base, filter => $configfilter);
  if (($mesg->code != 0) && ($mesg->code != LDAP_NO_SUCH_OBJECT)) {
    die $mesg->error;
  }

  if ($mesg->count > 0) {
    while (my ($key,$value) = each(%{$params})) {
      if (ref $value eq ref []) {
        $config->{"$key"} = ($mesg->entries)[0]->get_value(@$value);
      } else {
        if (($mesg->entries)[0]->get_value("$value")) {
          $config->{"$key"} = ($mesg->entries)[0]->get_value("$value");
        } else {
          $config->{"$key"} = "";
        }
      }
    }
  } else {
    die "Could not find configuration node in the LDAP (filter:$configfilter)".$die_endl;
  }

  return ($mesg->entries)[0];
}

#------------------------------------------------------------------------------
# generic functions for get settings functions
#
sub argonaut_get_generic_settings {
  my ($objectClass,$params,$config,$filter,$inheritance) = @_;
  unless (defined $inheritance) {
    $inheritance = 1;
  }

  my ($ldap,$ldap_base) = argonaut_ldap_handle($config);

  if ($filter =~ m/([0-9]{1,3}\.?){4}/ or $filter eq '*') {
    $filter = "(ipHostNumber=$filter)";
  } elsif ($filter !~ m/^\(/) {
    $filter = "($filter)";
  }

  my $mesg = $ldap->search( # perform a search
    base    => $ldap_base,
    filter  => "(&(objectClass=$objectClass)$filter)",
    attrs   => [values(%{$params}), 'dn', 'ipHostNumber', 'macAddress', 'gotoMode', 'fdMode', 'argonautDeploymentTimeframe' ]
  );

  my $settings = {
  };

  my $foundOC = 0;
  if (scalar($mesg->entries) > 1) {
    die "Several computers matches $filter.$die_endl";
  } elsif (scalar($mesg->entries) == 0) {
    unless ($inheritance) {
      die "This computer ($filter) is not configured in LDAP to run this module (missing service $objectClass).$die_endl";
    }
    $mesg = $ldap->search( # Get the system object
      base    => $ldap_base,
      filter  => $filter,
      attrs   => [values(%{$params}), 'dn', 'ipHostNumber', 'macAddress', 'gotoMode', 'fdMode', 'argonautDeploymentTimeframe' ]
    );
    if (scalar($mesg->entries) > 1) {
      die "Several computers matches $filter.$die_endl";
    } elsif (scalar($mesg->entries) < 1) {
      die "There is no computer matching $filter.$die_endl";
    }
  } else {
    $foundOC = 1;
    while (my ($key,$value) = each(%{$params})) {
      if (ref $value eq ref []) {
        $settings->{"$key"} = ($mesg->entries)[0]->get_value(@$value);
      } elsif (($mesg->entries)[0]->get_value("$value")) {
        $settings->{"$key"} = ($mesg->entries)[0]->get_value("$value");
      } else {
        $settings->{"$key"} = "";
      }
    }
  }

  $settings->{'dn'}   = ($mesg->entries)[0]->dn();
  $settings->{'mac'}  = ($mesg->entries)[0]->get_value("macAddress");
  $settings->{'ip'}   = ($mesg->entries)[0]->get_value("ipHostNumber");
  if (($mesg->entries)[0]->exists('fdMode')) {
    $settings->{'locked'} = ($mesg->entries)[0]->get_value("fdMode") eq 'locked';
  } elsif (($mesg->entries)[0]->exists('gotoMode')) {
    $settings->{'locked'} = ($mesg->entries)[0]->get_value("gotoMode") eq 'locked';
  } else {
    $settings->{'locked'} = 0;
  }
  $settings->{'timeframes'} = ($mesg->entries)[0]->get_value('argonautDeploymentTimeframe', asref => 1);

  my $dn = ($mesg->entries)[0]->dn();
  my $mesgGroup = $ldap->search( # Get the group object
    base   => $ldap_base,
    filter => "(&(objectClass=$objectClass)(member=$dn))",
    attrs => [values(%{$params}), 'argonautDeploymentTimeframe']
  );

  if (scalar($mesgGroup->entries) == 1) {
    if (not defined $settings->{'timeframes'}) {
      $settings->{'timeframes'} = ($mesgGroup->entries)[0]->get_value('argonautDeploymentTimeframe', asref => 1);
    }
  }

  if (not $foundOC) {
    if (scalar($mesgGroup->entries) == 1) {
      while (my ($key,$value) = each(%{$params})) {
        if (ref $value eq ref []) {
          $settings->{"$key"} = ($mesgGroup->entries)[0]->get_value(@$value);
        } elsif (($mesgGroup->entries)[0]->get_value("$value")) {
          $settings->{"$key"} = ($mesgGroup->entries)[0]->get_value("$value");
        } else {
          $settings->{"$key"} = "";
        }
      }
      return $settings;
    } else {
      die "This computer ($filter) is not configured in LDAP to run this module (missing service $objectClass).$die_endl";
    }
  }

  return $settings;
}

#------------------------------------------------------------------------------
# get server argonaut settings
#
sub argonaut_get_server_settings {
  my ($config,$ip) = @_;
  if ((not defined $ip) or ($ip eq "")) {
    $ip = "*";
  }
  return argonaut_get_generic_settings(
    'argonautServer',
    {
      'ip'                    => "ipHostNumber",
      'port'                  => "argonautPort",
      'protocol'              => "argonautProtocol",
      'token'                 => "argonautServerToken",
      'keyfile'               => "argonautKeyPath",
      'certfile'              => "argonautCertPath",
      'cacertfile'            => "argonautCaCertPath",
      'certcn'                => "argonautCertCN",
      'iptool'                => "argonautIpTool",
      'delete_finished_tasks' => "argonautDeleteFinished",
      'fetch_packages'        => "argonautFetchPackages",
      'interface'             => "argonautWakeOnLanInterface",
      'logdir'                => "argonautLogDir"
    },
    $config,$ip
  );
}

#------------------------------------------------------------------------------
# get client argonaut settings
#
sub argonaut_get_client_settings {
  return argonaut_get_generic_settings(
    'argonautClient',
    {
      'port'        => "argonautClientPort",
      'protocol'    => "argonautClientProtocol",
      'keyfile'     => "argonautClientKeyPath",
      'certfile'    => "argonautClientCertPath",
      'cacertfile'  => "argonautClientCaCertPath",
      'certcn'      => "argonautClientCertCN",
      'interface'   => "argonautClientWakeOnLanInterface",
      'logdir'      => "argonautClientLogDir",
      'taskidfile'  => "argonautTaskIdFile"
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
# get fuse settings
#
sub argonaut_get_fuse_settings {
  return argonaut_get_generic_settings(
    'argonautFuseConfig',
    {
      'default_mode'        => 'argonautFuseDefaultMode',
      'logdir'              => 'argonautFuseLogDir',
      'pxelinux_cfg'        => 'argonautFusePxelinuxCfg'
    },
    @_
  );
}

#------------------------------------------------------------------------------
# check if we are in an authorized time frame - Returns true if we are
#
sub argonaut_check_time_frames {
  my ($settings) = @_;
  if (not defined $settings->{'timeframes'}) {
    return 1;
  }
  foreach my $frame (@{$settings->{'timeframes'}}) {
    if ($frame =~ m/(\d\d)(\d\d)-(\d\d)(\d\d)/) {
      my ($sec,$min,$hour) = gmtime(time());
      my $begin = ($1 * 60) + $2;
      my $end   = ($3 * 60) + $4;
      my $now   = ($hour * 60) + $min;
      if ($begin > $end) {
        # Frame over midnight
        $end += 24 * 60;
        if ($now < $begin) {
          $now += 24 * 60;
        }
      }
      if ($now < $begin) {
        # Too soon
        next;
      } elsif ($now > $end) {
        # Too late
        next;
      }
      return 1;
    } else {
      die "Invalid value in time frames: $frame".$die_endl;
    }
  }
  return 0;
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
# Hash token using SSHA scheme
#
sub argonaut_gen_ssha_token {
  my ($token, $salt) = @_;
  if (not defined $salt) {
    $salt = argonaut_gen_random_str(8);
  }

  my $ctx = Digest::SHA->new(1);
  $ctx->add($token);
  $ctx->add($salt);

  return '{SSHA}'.encode_base64($ctx->digest.$salt, '');
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Check if token match ssha hash
#
sub argonaut_check_ssha_token {
  my ($hash, $token) = @_;

  my $salt = substr(decode_base64(substr($hash, 6)), 20);

  if ($hash eq argonaut_gen_ssha_token($token, $salt)) {
    return 1;
  } else {
    return 0;
  }
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

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
