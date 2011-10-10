# Copyright (c) 2008 Landeshauptstadt München
# Copyright (C) 2011 FusionDirectory project
#
# Author: Matthias S. Benkmann
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

package Argonaut::Common;

use strict;
use Net::LDAP;
use Net::LDAP::Constant qw(LDAP_NO_SUCH_OBJECT LDAP_REFERRAL);
use URI;

my $iptool = "ifconfig";

BEGIN
{
  use Exporter ();
  use vars qw(%EXPORT_TAGS @ISA $VERSION);
  $VERSION = '20080116';
  @ISA = qw(Exporter);

  %EXPORT_TAGS = (
    'ldap' => [qw(
      &goto_ldap_parse_config
      &goto_ldap_parse_config_ex
      &goto_ldap_parse_config_multi
      &goto_ldap_fsearch
      &goto_ldap_rsearch
      &goto_ldap_is_single_result
      &goto_ldap_split_dn
      &goto_ldap_init
      &goto_search_repo_server
      &goto_search_parent_repo_server
    )],
    'file' => [qw(
      &goto_file_write
      &goto_file_chown
    )],
    'array' => [qw(
      &goto_array_find_and_remove
    )],
    'string' => [qw(
      &goto_gen_random_str
    )],
     'misc' => [qw(
      &goto_options_parse
      &goto_get_pid_lock
      &goto_load_modules
      &goto_get_mac
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
sub goto_get_mac {
    my ($interface) = @_;
    my $mac = `LANG=C $iptool $interface | awk '/$interface/{ print \$5 }'`;
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
#
# These values are just filled, if they weren't provided,
# i.e. 
#
sub goto_ldap_init {
  my( $ldap_conf, $prompt_dn, $bind_dn, 
      $prompt_pwd, $bind_pwd, $obfuscate_pwd ) = @_;
  my %results;

  # Parse ldap config
  my ($base,$ldapuris) = goto_ldap_parse_config( $ldap_conf );
  %results = ( 'BASE' => $base, 'URIS' => $ldapuris);

  return( "Couldn't find LDAP base in config!" ) if( ! defined $base );
  return( "Couldn't find LDAP URI in config!" ) if( ! defined $ldapuris );

  # Create handle
  my $ldap = Net::LDAP->new( $ldapuris ) ||
    return( "LDAP 'new' error: '$@' with parameters '".join(",",@{$ldapuris})."'" );
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

  return( "LDAP bind error: " . $mesg->error . ' (' . $mesg->code . ")\n" )
    if( 0 != $mesg->code );

  return \%results;
}

#------------------------------------------------------------------------------
sub goto_ldap_parse_config
{
  my ($ldap_config) = @_;

  $ldap_config = $ENV{ 'LDAPCONF' }
    if( !defined $ldap_config && exists $ENV{ 'LDAPCONF' } );
  $ldap_config = "/etc/ldap/ldap.conf" 
    if( !defined $ldap_config );

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
sub goto_ldap_parse_config_ex
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
sub goto_ldap_split_dn {
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
sub goto_ldap_parse_config_multi
{
  my ($ldap_config) = @_;

  # Indicat, if it's a user or global config
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
#----------------------------------------------------------------------------
# search the parent(s) fai repo(s) declared in FusionDirectory
sub goto_search_parent_repo_server {
  my ($handle,$base,$cn) = @_;
  my @attrs = ( 'FAIrepository' );
  my ($sresult) = goto_ldap_rsearch( $handle, $base, '',
      "(&(objectClass=FAIrepositoryServer)(cn=${cn}))",
      "one", "ou=servers,ou=systems", \@attrs );
  return goto_ldap_is_single_result( $sresult, 1 );
}

#----------------------------------------------------------------------------
# search if there is a fai repo for the server mac address

sub goto_search_repo_server {
  my ($handle,$base,$mac) = @_;
  my @attrs = ( 'FAIrepository', 'cn' );
  my $sresult = $handle->search(
      base => "$base",
      filter => "(&(objectClass=FAIrepositoryServer)(macAddress=${mac}))",
      attrs => \@attrs );
  return ( $sresult ); 
}

#------------------------------------------------------------------------------
#
sub goto_file_write {

	my @opts = @_;
	my $len = scalar @_;
	($len < 2) && return;

	my $filename = shift;
	my $data = shift;

	open (SCRIPT,">${filename}") || warn "Can't create ${filename}. $!\n";
	print SCRIPT $data;
	close(SCRIPT);

  ($opts[2] ne "") && chmod oct($opts[2]),${filename};
	($opts[3] ne "") && goto_file_chown(${filename}, $opts[3]);
}

#------------------------------------------------------------------------------
#
sub goto_file_chown
{
  my @owner = split('.',$_[1]);
  my $filename = $_[0];
  my ($uid,$gid);
  $uid = getpwnam($owner[0]);
  $gid = getgrnam($owner[1]);
  
  chown $uid, $gid, $filename;
}

#------------------------------------------------------------------------------
#
# Common checks for forward and reverse searches
#
sub goto_ldap_search_checks {
  my( $base, $sbase ) = (@_)[1,2];

  if( scalar @_ < 3 ) {
    warn( "goto_ldap_search needs at least 3 parameters" );
    return;
  };

  if( defined $sbase && (length($sbase) > 0) ) {
    # Check, if $sbase is a base of $base
    if( $sbase ne substr($base,-1 * length($sbase)) ) {
      warn( "goto_ldap_search: (1) '$sbase' isn't the base of '$base'" );
      return;
    }

    $base = substr( $base, 0, length( $base ) - length( $sbase ) );

    # Check, if $base ends with ',' after $sbase strip
    if( ',' ne substr( $base, -1 ) ) {
      warn( "goto_ldap_search: (2) '$sbase' isn't the base of '$base'" );
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
sub goto_ldap_rsearch {
  use Switch;

  my ($ldap,$base,$sbase,$filter,$scope,$subbase,$attrs) = @_;

  ( $base, $sbase ) = goto_ldap_search_checks( @_ );
  return if( ! defined $base );

  my (@rdns,$search_base,$mesg);

  @rdns = goto_ldap_split_dn( $base );
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
# See goto_ldap_fsearch
#
# sbase = start base
#
# Example searches in:
#   ou=do,ou=very,ou=well
#   ou=do,ou=me,ou=very,ou=well
#   ou=do,ou=test,ou=me,ou=very,ou=well
# 
sub goto_ldap_fsearch {
  use Switch;

  my ($ldap,$base,$sbase,$filter,$scope,$subbase,$attrs) = @_;

  ( $base, $sbase ) = goto_ldap_search_checks( @_ );
  return if( ! defined $base );

  my (@rdns,$search_base,$mesg,$rdn_count);

  @rdns = reverse goto_ldap_split_dn( $base );
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
#
# $search_result = Net::LDAP::Serach
# $get_entry     = boolean
#
# if $get_entry == true,  return $entry 
#               == false, return 1
#
# returns 0 on failure
#
sub goto_ldap_is_single_result {
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
sub goto_array_find_and_remove {
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
sub goto_gen_random_str {
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
# Get a lockfile and check for already running processes
#
# @param string $cmd: application name to check in proc
# @param string $pidfile: lockfile name
# @return undef, $errstr or LOCKFILE handle
#
sub goto_get_pid_lock {
  my( $cmd, $pidfile ) = @_;
  my( $LOCK_FILE, $pid );

  # Check, if we are already running
  if( open($LOCK_FILE, "<$pidfile") ) {
    $pid = <$LOCK_FILE>;
    if( defined $pid ) {
      chomp( $pid );
      if( -f "/proc/$pid/stat" ) {
        my($stat) = `cat /proc/$pid/stat` =~ m/$pid \((.+)\).*/;
        if( "$cmd" eq $stat ) {
          close( $LOCK_FILE );
          return( undef, "Already running" );
        }
      }
    }
    close( $LOCK_FILE );
    unlink( $pidfile );
  }

  # Try to open PID file
#  if (!sysopen($LOCK_FILE, $pidfile, O_WRONLY|O_CREAT|O_EXCL, 0644)) {
  if (!sysopen($LOCK_FILE, $pidfile,0644)) {
    my $msg = "Couldn't obtain lockfile '$pidfile': ";

    if (open($LOCK_FILE, '<', $pidfile)
     && ($pid = <$LOCK_FILE>))
    {
     chomp($pid);
     $msg .= "PID $pid";
    } else {
      $msg .= $!;
    }

    return( undef, $msg );
  }

  return( $LOCK_FILE ); 
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dynamically load perl modules as plugins
#
# @param string $modules_path: directory for module lookup
# @param string $reg_function: function name to call for registration
# @param string $reg_params: perl parameters for the function call
# @param sub $reg_init: function to call with the result of the registration
#                       result will be saved as the value of 
#                       $registered_modules{ $mod_name }
# @return hashref of registered modules, arrayref of error strings or undef
#
sub goto_load_modules {
  my( $modules_path, $reg_func, $reg_params, $reg_init ) = @_;
  my %registered_modules;
  my @errors;
  my $errorref = \@errors;
  $reg_params = '' if( ! defined $reg_params );

  if( ! opendir (DIR, $modules_path) ) {
    push( @errors, "ERROR while loading modules from directory $modules_path : $!\n" );
    return( undef, \@errors );
  }

  my $abs_modules = abs_path( $modules_path );
  push( @INC, $abs_modules );

  while (defined (my $file = readdir (DIR))) {
    next if( $file !~ /([^\.].+)\.pm$/ );
    my $mod_name = $1;

    eval "require '$file';";
    if ($@) {
      my $import_error = $@;
      push( @errors, "ERROR: could not load module $file" );
      for my $line (split( "\n", $import_error )) {
        push( @errors, " perl: $line" );
      }
    } else {
      my $result = eval( "${mod_name}::${reg_func}(${reg_params});" );
      if( (! $@) && $result ) {
        $result = $reg_init->( $mod_name, $result ) if( defined $reg_init );
        $registered_modules{ $mod_name } = $result;
      }
      else { push( @errors, $@ ); }
    }
  }
  close (DIR);

  for( my $i = 0; $i < scalar @INC; $i++ ) {
    if( $INC[ $i ] eq $abs_modules ) {
      splice( @INC, $i, 1 );
      last;
    }
  }

  $errorref = undef if( ! scalar @errors );
  return( \%registered_modules, \@errors );
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Parse options from array into hash
#
# Copied from Net::LDAP
#
sub goto_options_parse {
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
