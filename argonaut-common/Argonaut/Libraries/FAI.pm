#######################################################################
#
# Argonaut::FAI packages - functions to get info for install from ldap
#
# Copyright (c) 2008 Landeshauptstadt München
# Copyright (C) 2011-2015 FusionDirectory project
#
# Authors: Jan-Marek Glogowski
#          Come Bernigaud
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

package Argonaut::FAI;

use strict;
use warnings;

use 5.008;

use Data::Dumper;
use Net::LDAP;
use File::Path;

use Argonaut::Libraries::Common qw(:ldap :string :file);

BEGIN
{
  use Exporter ();
  use vars qw(%EXPORT_TAGS @ISA $VERSION);
  $VERSION = '2015-02-03';
  @ISA = qw(Exporter);

  %EXPORT_TAGS = (
    'flags' => [qw(
      FAI_FLAG_VERBOSE
      FAI_FLAG_DRY_RUN
    )]
  );

  Exporter::export_ok_tags(keys %EXPORT_TAGS);
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Constructor for Argonaut::FAI object
#
# $ldap    = Net::LDAP handle
# %options = Hash of options like (Net::LDAP)
#
sub new {
  my $self = shift;
  my $type = ref($self) || $self;
  my $args = &argonaut_options_parse;

  my $obj  = bless {}, $type;
  $obj->{ 'LDAP' } = undef;
  $obj->{ 'flags' } = 0;

  foreach my $arg (keys %$args) {
    $obj->{ $arg } = $args->{ $arg };
  }

  return $obj;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Get or set Net::LDAP handle
#
sub handle {
  my( $self, $ldap ) = @_;

  if( defined $ldap ) {
    return undef if( ! $ldap->isa( 'Net::LDAP' ) );
    $self->{ 'LDAP' } = $ldap;
  }
  else { return $self->{ 'LDAP' }; }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Get or set LDAP base DN
#
sub base {
  my( $self, $base ) = @_;

  if( defined $base ) {
    $self->{ 'base' } = $base;
  }
  else { return $self->{ 'base' }; }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Get or set the dump directory
#
sub dumpdir {
  my( $self, $dumpdir ) = @_;

  if( defined $dumpdir ) {
    $self->{ 'dumpdir' } = $dumpdir;
  }
  else { return $self->{ 'dumpdir' }; }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Get or set class flags
#

# Prints progress information to stdout
use constant FAI_FLAG_VERBOSE => 1;

# Suppresses any data
use constant FAI_FLAG_DRY_RUN => 2;

sub flags {
  my( $self, $flags ) = @_;

  if( defined $flags ) {
    if( 0 > $flags ) {
      $self->{ 'flags' } = 0;
      return;
    }
    $self->{ 'flags' } = $flags;
  }
  elsif( exists $self->{ 'flags' } ) {
    return $self->{ 'flags' };
  }
  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self    = Argonaut::FAI handle
# $release = Release version
# $force   = Ignore cached values and recheck
#
# Returns \@rdns, \@releases
#  The versions RDNs and their corresponding release name.
#
sub release_check {
  my( $self, $release, $force ) = @_;

  my $fai_base = 'ou=fai,ou=configs,ou=systems';
  my @result_rdns = ();

  # Return cached values if not enforced
  if( ! defined $force && $force ) {
    return $self->{ 'CHECKS' }{ $release }
      if( exists $self->{ 'CHECKS' }{ $release } );
  }

  my $ldap = $self->{ 'LDAP' };
  my $base = $self->{ 'base' };

  my $mesg = $ldap->search(
    base => "$fai_base,$base",
    filter => "(&(objectClass=FAIbranch)(ou=$release))",
    attrs => [ 'ou', 'FAIstate' ],
    scope => 'sub' );
  $mesg->code && return( sprintf( "Release not found (%s)!"
    . " Release LDAP base not accessible (%s) - LDAP error: %s\n",
      $release, "$fai_base,$base", $mesg->error ) );

  my $full_base = 0;
  foreach my $entry ($mesg->entries()) {
    $full_base = 1;
    my $rdn = $entry->dn;
    $rdn =~ s/,$base$//;
    push( @result_rdns, $rdn );
  }

  return( sprintf( "No release base for (%s) found!\n", $release ) )
    if( ! $full_base  );

  $self->{ 'CHECKS' }->{ $release } =
    [ \@result_rdns ];

  return( \@result_rdns );
}


my %fai_items = (
  'debconf'   => [ undef, 'FAIdebconfInfo' ],
  'disk'      => [ 'FAIpartitionTable', undef ], # FAIpartitionDisk, FAIpartitionEntry
  'hooks'     => [ 'FAIhook', 'FAIhookEntry', 'cn', 'FAItask', 'FAIscript' ],
  'packages'  => [ 'FAIpackageList', 'FAIpackageList' ],
  'profiles'  => [ 'FAIprofile' ],
  'scripts'   => [ 'FAIscript', 'FAIscriptEntry', 'cn', 'FAIpriority', 'FAIscript' ],
  'templates' => [ 'FAItemplate', 'FAItemplateEntry' ],
  'variables' => [ 'FAIvariable', 'FAIvariableEntry', 'cn', 'FAIvariableContent' ],
);


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self    = Argonaut::FAI handle
# $release = Release version
# $flags   = Bit flags for cache lookup
#            FAI_CACHE_GENERATE = generate cache if not available
#            FAI_CACHE_FORCE    = force cache regeneration
#            Defaults to FAI_CACHE_GENERATE.
#
# Returns a hashref including the classes for the FAI types
#  $result->{ ''profile', 'hook', ... }->{ 'class' }
#  In case of profiles it points to a hashref of profile subclasses
#
use constant FAI_CACHE_GENERATE => 1;
use constant FAI_CACHE_FORCE    => 2;

sub get_class_cache {
  my( $self, $release, $flags ) = @_;

  # Set variables from flags
  $flags = 1 if( ! defined $flags );
  my $generate = $flags & FAI_CACHE_GENERATE ? 1 : 0;
  my $force    = $flags & FAI_CACHE_FORCE    ? 1 : 0;

  # Return cached values if not enforced or looked up
  if( !$force ) {
    return $self->{ 'FAI_TREES' }{ $release }
      if( exists $self->{ 'FAI_TREES' }{ $release } );
    return undef if( ! $generate );
  }

  return $self->generate_class_cache( $release, $force );
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self    = Argonaut::FAI handle
# $release = Release version
#
# Returns a hashref including the classes for the FAI types
#  $result->{ ''profile', 'hook', ... }->{ 'class' }
#  In case of profiles it points to a hashref of profile subclasses
#
sub generate_class_cache {
  my( $self, $release, $force ) = @_;
  my %cache = ();

  my( $rdns ) = $self->release_check( $release, $force );
  return $rdns if( ref( $rdns ) ne 'ARRAY' );

  my $ldap = $self->{ 'LDAP' };
  my $base = $self->{ 'base' };

  # Check all FAI OUs for classnames
  while( my( $type, $class ) = each %fai_items) {

    # We skip debconf infos
    next if( ! defined @{$class}[0] );

    my $mesg = $ldap->search(
        base => "ou=${type},@{$rdns}[0],${base}",
        filter => '(objectClass=' . @{$class}[0] . ')',
        scope => 'one',
        attrs => [ 'cn', 'FAIclass', 'FAIstate' ]);

    next if( 32 == $mesg->code ); # Skip non-existent objects
    return( "LDAP search error: " . $mesg->error . ' (' . $mesg->code . ")\n" )
      if( 0 != $mesg->code );

    $cache{ $type } = ();
    next if( 0 == $mesg->count );

    if( $type eq 'profiles' ) {
      next if( 0 == $mesg->count );

      foreach my $entry ($mesg->entries()) {
        my $cn = $entry->get_value( 'cn' );
        my $classlist_str = $entry->get_value( 'FAIclass' );
        $cache{ $type }{ $cn }{ '_classes' } = ();
        $cache{ $type }{ $cn }{ '_state' } = $entry->get_value( 'FAIstate' );
        foreach my $profile_class (split( ' ', $classlist_str )) {
          if( ":" eq substr( $profile_class, 0, 1 ) ) {
            warn( "Release '$cn' found in profile '$class' of '$release'." );
          } else {
            push( @{$cache{ $type }{ $cn }{ '_classes' }}, $profile_class );
          }
        }
      }
    }
    else {
      foreach my $entry ($mesg->entries()) {
        $cache{ $type }{ $entry->get_value( 'cn' ) } = undef;
        $cache{ 'debconf' }{ $entry->get_value( 'cn' ) } = undef
          if( 'packages' eq $type );
      }
    }
  }

  $self->{ 'FAI_TREES' }{ $release } = \%cache;
  return \%cache;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self    = Argonaut::FAI handle
# $release = Release version
# $flags   = @see get_class_cache
#
# Returns a hashref including the classes for the FAI types
#  $result->{ ''profile', 'hook', ... }->{ 'class' }
#  In case of profiles it points to a hashref of profile subclasses
#
sub extend_class_cache {
  my( $self, $release, $flags ) = @_;

  # Set variables from flags
  $flags = 1 if( ! defined $flags );
  my $generate = $flags & FAI_CACHE_GENERATE ? 1 : 0;
  my $force    = $flags & FAI_CACHE_FORCE    ? 1 : 0;

  my( $rdns ) = $self->release_check( $release, $force );
  return $rdns if( ref( $rdns ) ne 'ARRAY' );

  my %cache = ();
  my $cache_ref;

  # Return cached values if not enforced
  if( ! $force ) {
    $cache_ref = $self->{ 'FAI_TREES' }{ $release }
      if( exists $self->{ 'FAI_TREES' }{ $release } );
    return $self->{ 'FAI_TREES' }{ $release }
      if( defined $cache_ref &&
          defined $cache_ref->{ 'extended' } );
    return undef if( ! $generate );
  }

  $cache_ref = $self->get_class_cache( $release, $flags )
    if( ! defined $cache_ref );
  return $cache_ref if( 'HASH' ne ref( $cache_ref ) );

  my $ldap = $self->{ 'LDAP' };
  my $base = $self->{ 'base' };
  my( $entry, $type, $faiclasses );

  # Check all FAI OUs for classnames
  while( ($type, $faiclasses) = each %$cache_ref ) {

    # Skip, if this entry is not an FAI type
    next if(! exists $fai_items{ $type });

    # Skip, if this type doesn't have additional information
    my @attrs = @{$fai_items{ $type }};
    next if( 1 == scalar @attrs );
    my $objclass = $attrs[ 1 ];

    # Filter attributes
    @attrs = splice( @attrs, 2 );
    push( @attrs, 'FAIstate' ) if( scalar @attrs );

    foreach my $class (keys( %{$faiclasses} )) {
      my $mesg;

      # For package lists we have to store the actual data in an extra object
      if( 'debconf' eq $type ) {
        $mesg = $ldap->search(
            base => "cn=${class},ou=packages,@{$rdns}[0],${base}",
            filter => "(objectClass=$objclass)",
            scope => 'one' );
      }
      elsif( 'packages' eq $type ) {
        $mesg = $ldap->search(
            base => "cn=${class},ou=${type},@{$rdns}[0],${base}",
            filter => "(objectClass=$objclass)",
            scope => 'base' );
        return( "LDAP search error: " . $mesg->error . ' (' . $mesg->code . ")\n" )
          if( 0 != $mesg->code );

        # Store entries
        $cache_ref->{ ${type} }->{ ${class} } = ($mesg->entries())[0];
        next;
      }
      elsif( 'disk' eq $type ) {

#        print( "Disk config lookup for '${class}'...\n" );
        my $setup_storage = 0;

        my $class_base = "cn=${class},ou=${type},@{$rdns}[0],${base}";
        $mesg = $ldap->search(
            base => ${class_base},
            filter =>
              '(|(objectClass=FAIpartitionDisk)(objectClass=FAIpartitionEntry)(objectClass=FAIpartitionTable))',
            scope => 'sub' );
        return( "LDAP search error: " . $mesg->error . ' (' . $mesg->code . ")\n" )
          if( 0 != $mesg->code );

        # Decode disks and partition tables
        my @entries = $mesg->entries();
        my %disk_configs;
        my $checked_entries = scalar @entries;

        while( scalar @entries ) {
          $entry = shift( @entries );
          my @objclasses = $entry->get_value( 'objectClass' );
          my $valid_object = 0;

          foreach my $obj (@objclasses) {
            my $dn_tail;
            my @rdns;

            # Check partition
            if( $obj =~ /^FAIpartitionTable$/i ) {
              if (defined $entry->get_value( 'FAIpartitionMethod' )){
                $setup_storage = $entry->get_value( 'FAIpartitionMethod' ) eq 'setup-storage';
              }
              $entry = undef;
              last;
            }

            # Check disk
            if( $obj =~ /^FAIpartitionDisk$/i ) {
              @rdns = argonaut_ldap_split_dn( $entry->dn() );
              shift( @rdns );
              $dn_tail = join( ',', @rdns );
              my $cn = $entry->get_value( 'cn' );

              last if( $dn_tail !~ /^${class_base}$/
                || (exists $disk_configs{${cn}}) );

              if( ! is_removed( $entry ) ) {
                my %partitions = ();
                $disk_configs{${cn}} = \%partitions;
                $disk_configs{${cn}}->{'disk'} = $entry;
                $disk_configs{${cn}}->{'setup-storage'} = $setup_storage;
#                print( " + disk '${cn}'\n" );
              }
              else { $disk_configs{${cn}} = undef; }
              $entry = undef;
              $valid_object = 1;
              last;
            }

            # Check partition
            if( $obj =~ /^FAIpartitionEntry$/i ) {
              my @rdns = argonaut_ldap_split_dn( $entry->dn() );
              shift @rdns;
              my $disk = shift @rdns;
              $dn_tail = join( ',', @rdns );
              ($disk) = $disk =~ /^[^=]+=(.*)/;

              last if( $dn_tail !~ /^${class_base}$/ );

              # Since the LDAP result is unordered, there might be a
              # valid disk later - mark partition as valid
              $valid_object = 1;
              last if( ! defined $disk_configs{${disk}} );

              $disk_configs{${disk}}->
                { $entry->get_value( 'FAIpartitionNr' ) } = $entry;
#              print( "   + partition '" . $entry->get_value( 'FAIpartitionNr' )
#                                        . "' to disk '${disk}'\n" );
              $entry = undef;
              last;
            }
          }

          $checked_entries--;
          if( defined $entry ) {
            # If we didn't store the entry yet, check if it's valid
            if( $checked_entries < 0 ) {
              print( "Unable to find disk for partition '"
                    . $entry->get_value( 'cn' ) . "' - skipped\n" );
              next;
            }
            if( ! $valid_object ) {
              print( "Invalid disk config entry '"
                    . $entry->dn() . "' - skipped\n" );
              next;
            }
            push( @entries, $entry ) if( defined $entry );
          }
        }

        # Store disk config
        $cache_ref->{ ${type} }->{ ${class} } = \%disk_configs;
        next;
      }
      else {
        my %search = (
          base => "cn=${class},ou=${type},@{$rdns}[0],${base}",
          filter => "(objectClass=$objclass)",
          scope => 'one'
        );
        $search{ 'attrs' } = \@attrs if( scalar @attrs );
        $mesg = $ldap->search( %search );

      }

      return( sprintf( "LDAP search error at line %i: %s (%i)\n", __LINE__, $mesg->error, $mesg->code ) )
        if( 0 != $mesg->code );

      # Store entries
      if( 0 != $mesg->count ) {
        my %values;
        foreach my $entry ($mesg->entries()) {
          my $key;
          if( 'debconf' eq ${type} ) {
            $key = $entry->get_value( 'FAIvariable' );
          } elsif( 'templates' eq ${type} ) {
            $key = $entry->get_value( 'FAItemplatePath' );
          } else { $key = $entry->get_value( 'cn' ); }
          if( exists $values{ $key } )
            { warn( "Duplicated key '$key' in '$class' for  type '$type'" ); }
          else { $values{ $key } = $entry; }
        }
        $cache_ref->{ ${type} }->{ ${class} } = \%values;
      } else { delete( $cache_ref->{ ${type} }->{ ${class} } ); }
    }
  }

  $cache_ref->{ 'extended' } = 1;
  $self->{ 'FAI_TREES' }{ $release } = $cache_ref;

  return $self->{ 'FAI_TREES' }{ $release };
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Verify, if the FAI object has the 'removed' state
#
# $entry = Net::LDAP::Entry
#
# Returns true, if the 'FAIstate' contains a removed
#
sub is_removed {
  my $entry = shift;
  my $state = $entry->get_value( 'FAIstate' );
  my %states = map { $_ => 1 } split( "\\|", $state ) if( defined $state );
  return 1 if( exists $states{ 'removed' } );
  return 0;
}

# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Common init code for all dump_ functions
#
# $self         = Argonaut::FAI handle
# $release      = Release to dump
# $classref     =
# $flags        =
# $type         =
# $nomerge      =
#
# $classref     = Arrayref to the requested FAIclass list (already expanded)
# $dumpdir      =
# $cow_merge    =
#
sub init_dump_function {
  my( $self, $release, $classref, $flags, $type ) = @_;

  my $dumpdir = $self->{ 'dumpdir' };
  my $typeref = $self->extend_class_cache( $release, $flags )->{ $type };

  # Fill $classref with all classes, if not supplied
  if( ! defined $classref ) {
    my %seen;

    foreach my $item (keys %$typeref) {
      $seen{ $item } = 1;
    }

    my @classlist = keys( %seen );
    $classref = \@classlist;
  }

  # Merge release hashes into COW hash
  my %cow_merge;
  foreach my $class (@$classref) {
    next if( ! exists $typeref->{ $class } );
    if( ref( $typeref->{ $class } ) eq 'HASH' ) {
      while( my($key, $value) = each %{$typeref->{ $class }} ) {
        $cow_merge{ $class }{ $key } = $value;
      }
    } else {
      $cow_merge{ $class } = $typeref->{ $class };
    }
  }

  return( $classref, $dumpdir, \%cow_merge );
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dumps variables from class cache
#
# $self      = Argonaut::FAI handle
# $release   = Release string
# $classref  = Arrayref to the requested FAIclass list (already expanded)
# $flags     = @see get_class_cache, but defaults to 0;
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_variables {
  my( $self, $release, $classref, $flags ) = @_;
  my( $dumpdir, $cow_cacheref );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'variables' );
  return $classref if( ! defined $dumpdir );

  foreach my $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );
    my %vars = ();
    foreach my $entry (values %{$cow_cacheref->{ $class }}) {
      next if( is_removed( $entry ) );
      my $cn = $entry->get_value( 'cn' );
      $vars{ $cn } = $entry->get_value( 'FAIvariableContent' );
    }

    next if( 0 == scalar keys( %vars ) );

    if( $self->{ 'flags' } & FAI_FLAG_VERBOSE ) {
      print( "Generate variable file for class '${class}'.\n" );
      print( "  Vars: " . join( ", ", keys %vars ) . "\n" );
    }

    next if( $self->{ 'flags' } & FAI_FLAG_DRY_RUN );

    if( ! -d "$dumpdir/class" ) {
      eval { mkpath( "$dumpdir/class" ); };
      return( "Can't create dir '$dumpdir/class': $!\n" ) if( $@ );
    }

    open (FAIVAR,">$dumpdir/class/${class}.var")
        || return( "Can't create '$dumpdir/class/${class}.var': $!\n" );
    while( my( $key, $value ) = each( %vars ) ) {
      print( FAIVAR "${key}='${value}'\n" );
    }
    close (FAIVAR);
  }

  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dumps package lists from class cache
#
# $self      = Argonaut::FAI handle
# $release   = Release string
# $classref  = Arrayref to the requested FAIclass list (already expanded)
# $flags     = @see get_class_cache, but defaults to 0;
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_package_list {
  my( $self, $release, $classref, $flags ) = @_;
  my( $dumpdir, $cow_cacheref );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'packages' );
  return $classref if( ! defined $dumpdir );

  my( $class, $entry, $method );

  if( ! -d "$dumpdir/package_config" ) {
    eval { mkpath( "$dumpdir/package_config" ); };
    return( "Can't create dir '$dumpdir/package_config': $!\n" ) if( $@ );
  }

  my %uniq_sections = ();
  my %uniq_customs = ();
  foreach $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );
    $entry = $cow_cacheref->{ $class };
    $method = $entry->get_value( 'FAIinstallMethod' );

    print( "Generate package list for class '${class}'.\n" )
      if( $self->{ 'flags' } & FAI_FLAG_VERBOSE );

    foreach my $section ( $entry->get_value( 'FAIdebianSection' ) ) {
      $uniq_sections{ $section } = undef;
    }

    foreach my $custom ( $entry->get_value( 'FAIcustomRelease' ) ) {
      $uniq_customs{ $custom } = undef;
    }

    next if( $self->{ 'flags' } & FAI_FLAG_DRY_RUN );

    open( PACKAGES, ">$dumpdir/package_config/$class" )
      ||  do_exit( 4, "Can't create $dumpdir/package_config/$class. $!\n" );
    print PACKAGES "PACKAGES $method\n";
    print PACKAGES join( "\n", $entry->get_value('FAIpackage') );
    print PACKAGES "\n";
    close( PACKAGES );
  }

  my @sections = keys( %uniq_sections );
  my @customs = keys( %uniq_customs );
  return( undef, \@sections, \@customs );
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dumps debconf information from class cache
#
# $self      = Argonaut::FAI handle
# $release   = Release string
# $classref  = Arrayref to the requested FAIclass list (already expanded)
# $flags     = @see get_class_cache, but defaults to 0;
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_debconf_info {
  my( $self, $release, $classref, $flags ) = @_;
  my( $dumpdir, $cow_cacheref );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'debconf' );
  return $classref if( ! defined $dumpdir );

  my( $entry );

  if( ! -d "$dumpdir/debconf" ) {
    eval { mkpath( "$dumpdir/debconf" ); };
    return( "Can't create dir '$dumpdir/debconf': $!\n" ) if( $@ );
  }

  foreach my $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );
    my @lines = ();
    foreach $entry (values %{$cow_cacheref->{ $class }}) {
      next if( is_removed( $entry ) );
      push( @lines, sprintf( "%s %s %s %s",
          $entry->get_value('FAIpackage'),
          $entry->get_value('FAIvariable'),
          $entry->get_value('FAIvariableType'),
          $entry->get_value('FAIvariableContent') ) );
    }

    next if( 0 == scalar @lines );

    open( DEBCONF, ">$dumpdir/debconf/$class" )
      ||  return( "Can't create $dumpdir/debconf/$class. $!\n" );
    print DEBCONF join( "\n", sort {$a cmp $b} @lines );
    print DEBCONF "\n";
    close( DEBCONF );
  }

  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dumps disk configurations from class cache
#
# $self      = Argonaut::FAI handle
# $release   = Release string
# $classref  = Arrayref to the requested FAIclass list (already expanded)
# $flags     = @see get_class_cache, but defaults to 0;
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_disk_config {
  my( $self, $release, $classref, $flags ) = @_;
  my( $cow_cacheref, $dumpdir );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'disk' );
  return $classref if( ! defined $dumpdir );

  if( ! -d "$dumpdir/disk_config" ) {
    eval { mkpath( "$dumpdir/disk_config" ); };
    return( "Can't create dir '$dumpdir/disk_config': $!\n" ) if( $@ );
  }

  my $first_lvm_disk= 1;
  my $disk_index= 0;
  my $setup_storage= 0;

  foreach my $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );
    my $disk_config = $cow_cacheref->{ $class };
    my( %all_disks, $disk, $entry );

    foreach my $type ("disk", "raid", "lvm") {
      foreach $disk (keys %{$disk_config}) {
        next if( ! defined $disk_config->{ $disk } );

        # Extract setup storage mode
        my $dc = $disk_config->{ $disk }->{ 'disk' };
        $setup_storage= $disk_config->{ $disk }->{ 'setup-storage' };

        # Extract disk information
        my $disk_type = "disk";
        my $disk_options = "";
        my $lvm_name= "";
        if (defined $dc->get_value('FAIdiskOption')) {
          foreach ($dc->get_value('FAIdiskOption')) {
            $disk_options= $disk_options . " " . $_;
          }
        }
        if (defined $dc->get_value('FAIdiskType')) {
          $disk_type = $dc->get_value('FAIdiskType');
        }

        # Skip workaround to manage order of disk types
        next if( $disk_type ne $type);

        # Update index
        my $disk_label= $disk_index."-".$disk;
        $all_disks{ $disk_label } = {};

        # In case of LVM, we need a special handling, because the volumes
        # get handled as disks internally
        if ($disk_type eq "lvm") {
          $lvm_name = $dc->get_value('cn');
          my $size = "";
          foreach ($dc->get_value('FAIlvmDevice')) {
            $size= $size . "," . $_;
          }
          $size=~ s/^.//;
          if ($first_lvm_disk) {
            $first_lvm_disk= 0;
            $all_disks{ $disk_label }{ 0 } = "disk_config lvm$disk_options\nvg $lvm_name $size\n";
          } else {
            $all_disks{ $disk_label }{ 0 } = "vg $lvm_name $size\n";
          }
        } else {
          $all_disks{ $disk_label }{ 0 } = "disk_config $disk$disk_options\n";
        }

        # Remove disk information from hash
        delete $disk_config->{ $disk }->{ 'disk' };
        delete $disk_config->{ $disk }->{ 'setup-storage' };

        my $logic_count = 4;
        my $primary_count = 0;

        foreach my $partition_nr (sort {$a <=> $b}
                                 (keys %{$disk_config->{ $disk }}) ) {
          my $line;
          my $dl = $disk_config->{ $disk }->{ $partition_nr };

          if ($dl->get_value('FAIpartitionType') eq 'primary'){
            $primary_count++;
          } else {
            $logic_count++;
          }

          my $part_flags = $dl->get_value('FAIpartitionFlags');
          my $mount_opts = $dl->get_value('FAImountOptions');
          $mount_opts = 'rw' if( ! defined $mount_opts || ($mount_opts eq '') );
          my $combined_opts= "";
          my $c_opts = $dl->get_value('FAIfsCreateOptions');
          my $t_opts = $dl->get_value('FAIfsTuneOptions');
          if (defined $c_opts) {
            $combined_opts= "createopts=\"$c_opts\" ";
          }
          if (defined $t_opts) {
            $combined_opts.= "tuneopts=\"$t_opts\"";
          }

          if ($setup_storage) {
            if ($disk_type eq 'lvm') {
              $line= sprintf( "%-20s %-18s %-12s %-10s %s %s\n",
                $lvm_name."-".$dl->get_value('cn'),
                $dl->get_value('FAImountPoint'),
                $dl->get_value('FAIpartitionSize'),
                $dl->get_value('FAIfsType'),
                $mount_opts,
                $combined_opts);
            } else {
              $line= sprintf( "%-20s %-18s %-12s %-10s %s %s\n",
                $dl->get_value('FAIpartitionType'),
                $dl->get_value('FAImountPoint'),
                $dl->get_value('FAIpartitionSize'),
                $dl->get_value('FAIfsType'),
                $mount_opts,
                $combined_opts);
            }
          } else {
            if (defined $part_flags && ($part_flags eq 'preserve') ){
              my $part_type;
              if ($dl->get_value('FAIpartitionType') eq 'primary'){
                $part_type = 'preserve' . $primary_count;
              } else {
                $part_type = 'preserve' . $logic_count;
              }

              $line = sprintf( "%-7s %-12s %-12s %-10s ; %s mounttype=uuid\n",
                $dl->get_value('FAIpartitionType'),
                $dl->get_value('FAImountPoint'),
                $part_type,
                $mount_opts,
                $dl->get_value('FAIfsOptions') );
            }
            elsif ($dl->get_value('FAIfsType') eq 'swap') {
              # Labels are limited to 15 chars
              my $swaplabel = 'swap-' . argonaut_gen_random_str( 10 );
              $line = sprintf( "%-7s %-12s %-12s %-10s ; mounttype=label label='%s'\n",
                $dl->get_value('FAIpartitionType'),
                $dl->get_value('FAImountPoint'),
                $dl->get_value('FAIpartitionSize'),
                $mount_opts, $swaplabel );
            }
            else {
              $line= sprintf( "%-7s %-12s %-12s %-10s ; %s %s mounttype=uuid\n",
                $dl->get_value('FAIpartitionType'),
                $dl->get_value('FAImountPoint'),
                $dl->get_value('FAIpartitionSize'),
                $mount_opts,
                $dl->get_value('FAIfsOptions'),
                $dl->get_value('FAIfsType') );
            }
          }

          $all_disks{ $disk_label }{ $partition_nr } = $line;
        }

        $disk_config->{ $disk }->{ 'disk' }= $dc;
        $disk_config->{ $disk }->{ 'setup-storage' }= $setup_storage;
      }

      $disk_index++;
    }

    my @disk_config_lines;
    if( %all_disks ) {
      foreach my $disk (sort {$a cmp $b} keys %all_disks) {
        foreach my $part (sort {$a <=> $b} keys %{$all_disks{ $disk }} ) {
          push( @disk_config_lines, $all_disks{ $disk }{ $part } );
        }
      }
    }

    open( DISK_CONFIG, ">$dumpdir/disk_config/${class}" )
        || return( "Can't create $dumpdir/disk_config/$class. $!\n" );
    print DISK_CONFIG join( '', @disk_config_lines );
    close( DISK_CONFIG );

    # Enable setup storage if needed
    if ($setup_storage && ! ($self->{ 'flags' } & FAI_FLAG_DRY_RUN)) {
      if( ! -d "$dumpdir/class" ) {
        eval { mkpath( "$dumpdir/class" ); };
        return( "Can't create dir '$dumpdir/class': $!\n" ) if( $@ );
      }

      open (FAIVAR,">>$dumpdir/class/${class}.var")
          || return( "Can't create/append '$dumpdir/class/${class}.var': $!\n" );
      print( FAIVAR "USE_SETUP_STORAGE=1\n" );
      close (FAIVAR);
    }

  }

  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Writes the file in 'FAI mode' and adds mode info
#
# $filename = full path to real file
# $data     = file data
# $mode     = file mode
# $owner    = file owner
# $class    = FAIclass, the file belongs to
#
# Returns nothing
#
sub write_fai_file {

  my( $filename, $data, $mode, $owner, $class ) = @_;
  my $fclass = '';

  return if( scalar @_ < 2 );

  # Append class to filename
  $fclass = '/' . $class if( defined $class );

  open( FILE,">${filename}${fclass}" )
    || return( "Can't create file '${filename}${fclass}': $!\n" );
  print( FILE $data ) if( defined $data );
  close( FILE );

  if( defined $class && ('' ne $class) ) {
    # ($owner,$group,$mode,$class) = split
    my (@modelines) = ();

    if( -f "${filename}/file-modes" ) {
      open( MODES, '<', "${filename}/file-modes" )
        || return( "Couldn't open modefile '${filename}/file-modes': $!\n" );
      (@modelines) = <MODES>;
      close( MODES );
    }

    open( MODES, '>', "${filename}/file-modes" )
      || return( "Couldn't open modefile '${filename}/file-modes': $!\n" );

    # Remove old mode entry from file-modes
    foreach my $line ( @modelines ) {
      chomp( $line );
      print( MODES "$line\n" ) if( ! ($line =~ /${class}$/) );
    }

    # Fix empty mode
    $mode = '0640' if( ! defined $mode || ($mode !~ /^0*[0-7]{1,4}$/) );

    # Fix empty owners
    if( defined $owner && ('' ne $owner) ) {
      $owner =~ tr/\.:/  /;
    } else {
      $owner = 'root root';
    }

    print( MODES "$owner $mode $class\n" );
    close( MODES );
  }
  else {
    chmod( oct($mode), ${filename} )
      if( defined $mode && ($mode =~ /^0*[0-7]{1,4}$/) );
    argonaut_file_chown( ${filename}, $owner )
      if( defined $owner && ($owner ne '') );
  }
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dumps scripts from class cache
#
# $self      = Argonaut::FAI handle
# $release   = Release string
# $classref  = Arrayref to the requested FAIclass list (already expanded)
# $flags     = @see get_class_cache, but defaults to 0;
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_scripts {
  my( $self, $release, $classref, $flags ) = @_;
  my( $cow_cacheref, $dumpdir );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'scripts' );
  return $classref if( ! defined $dumpdir );

  foreach my $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );

    if( ! -d "$dumpdir/scripts/${class}" ) {
      eval { mkpath( "$dumpdir/scripts/${class}" ); };
      return( "Can't create dir '$dumpdir/scripts/${class}': $!\n" ) if( $@ );
    }

    my @lines = ();
    foreach my $entry (values %{$cow_cacheref->{ $class }}) {
      my $name   = $entry->get_value( 'cn' );
      my $prio   = $entry->get_value( 'FAIpriority' );
      my $script_name = sprintf( '%02d-%s', $prio, $name );
      my $script_path = "${dumpdir}/scripts/${class}/${script_name}";

      if( is_removed( $entry ) ) {
        unlink( "${script_path}" ) if( -f "${script_path}" );
        next;
      }

      print( "Generate script '${script_name}' for class '${class}'.\n" )
        if( $self->{ 'flags' } & FAI_FLAG_VERBOSE );

      write_fai_file( "${script_path}",
          $entry->get_value( 'FAIscript' ), '0700' )
       if( ! ($self->{ 'flags' } & FAI_FLAG_DRY_RUN) );
    }
  }
  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# Dumps templates from LDAP
#
# $self      = Argonaut::FAI handle
# $release   = Release string
# $classref  = Arrayref to the requested FAIclass list (already expanded)
# $flags     = @see get_class_cache, but defaults to 0;
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_templates {
  my( $self, $release, $classref, $flags ) = @_;
  my( $cow_cacheref, $dumpdir );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'templates' );
  return $classref if( ! defined $dumpdir );

  my( $release_base ) = $self->release_check( $release );

  my $ldap = $self->{ 'LDAP' };
  my $base = $self->{ 'base' };

  if( ! -d "$dumpdir/files" ) {
    eval { mkpath( "$dumpdir/files" ); };
    return( "Can't create dir '$dumpdir/files': $!\n" ) if( $@ );
  }

  foreach my $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );

    foreach my $entry (values %{$cow_cacheref->{ $class }}) {
      my $template_path = $entry->get_value( 'FAItemplatePath' );
      chomp( $template_path );
      my $target_path = "${dumpdir}/files/${template_path}/${class}";

      # Remove removed files ;-)
      if( is_removed( $entry ) ) {
        unlink( "${target_path}" ) if( -f "${target_path}" );
        next;
      }

      if( ! -d "$dumpdir/files/$template_path" ) {
        eval { mkpath( "$dumpdir/files/$template_path" ); };
        return( "Can't create dir '$dumpdir/files/$template_path': $!\n" ) if( $@ );
      }

      print( "Generate template '${template_path}' for class '${class}'.\n" )
        if( $self->{ 'flags' } & FAI_FLAG_VERBOSE );

      write_fai_file( "${dumpdir}/files/${template_path}",
          $entry->get_value('FAItemplateFile'),
          $entry->get_value('FAImode'),
          $entry->get_value('FAIowner'), $class )
        if( ! ($self->{ 'flags' } & FAI_FLAG_DRY_RUN) );
    }
  }
  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self     = Argonaut::FAI handle
# $release  = Release version
# $classref = Arrayref of classes to dump (will be expanded)
#
# Returns undef, if no error occured, otherwise the error message
#
sub dump_hooks {
  my( $self, $release, $classref, $flags ) = @_;
  my( $dumpdir, $cow_cacheref );

  ( $classref, $dumpdir, $cow_cacheref )
    = $self->init_dump_function( $release, $classref, $flags, 'hooks' );
  return $classref if( ! defined $dumpdir );

  foreach my $class (@$classref) {
    next if( ! exists $cow_cacheref->{ $class } );

    if( ! -d "$dumpdir/hooks" ) {
      eval { mkpath( "$dumpdir/hooks" ); };
      return( "Can't create dir '$dumpdir/hooks': $!\n" ) if( $@ );
    }

    my @lines = ();
    foreach my $entry (values %{$cow_cacheref->{ $class }}) {
      my $task      = $entry->get_value( 'FAItask' );
      my $hook_path = "${dumpdir}/hooks/${task}.${class}";
      my $cn        = $entry->get_value( 'cn' );

      if( is_removed( $entry ) ) {
        unlink( "${hook_path}" ) if( -f "${hook_path}" );
        next;
      }

      print( "Generate hook '$cn' ($task) for class '${class}'.\n" )
        if( $self->{ 'flags' } & FAI_FLAG_VERBOSE );

      write_fai_file( ${hook_path},
          $entry->get_value( 'FAIscript' ), '0700' )
        if( ! ($self->{ 'flags' } & FAI_FLAG_DRY_RUN) );
    }
  }
  return undef;
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self     = Argonaut::FAI handle
# $release  = Release version
# $classref = Arrayref of classes to dump (will be expanded)
# $hostname = Host to use in classlist expansion
#
# Returns a hashref including the classes for the FAI types
#  $result->{ ''profile', 'hook', ... }->{ 'class' }
#  In case of profiles it points to a hashref of profile subclasses
# Returns error, sections and customs.
# error is undef if no error happened.
#
sub dump_release {
  my( $self, $release, $classref, $hostname ) = @_;
  my $cls_release;

  if( defined $classref ) {
    ($classref, $cls_release) = $self->resolve_classlist( $classref, $release, $hostname );
    return( $classref ) if( 'ARRAY' ne ref( $classref ) );
    $release = $cls_release if( ! defined $release );
  }

  return( "No release specified\n" ) if( ! defined $release );

  my $cacheref = $self->extend_class_cache( $release );
  return( $cacheref ) if( 'HASH' ne ref( $cacheref ) );

  return( "No dump directory specified" ) if( ! defined $self->{ 'dumpdir' } );
  my $dumpdir = $self->{ 'dumpdir' };
  $dumpdir .= '/class' if( defined $hostname );

  # Create dump directory and hosts classfile
  if( ! -d "${dumpdir}" ) {
    eval { mkpath( "${dumpdir}" ); };
    return( "Can't create dir '${dumpdir}': $!\n" ) if( $@ );
  }

  if( defined ${hostname} ) {
    open( CLASSLIST, ">${dumpdir}/${hostname}" )
      || return( "Can't create ${dumpdir}/${hostname}. $!\n" );
    print( CLASSLIST join( ' ', @${classref} ) );
    close( CLASSLIST );
  }

  # Add FAI standard classes for dump
  $classref = $self->expand_fai_classlist( $classref, $hostname )
    if( defined $classref );

  # Dump variables, packages, debconf, scripts, templates and disk_config
  my $dump_result = $self->dump_variables( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  my ($sections, $customs);
  ($dump_result, $sections, $customs) = $self->dump_package_list( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  $dump_result = $self->dump_debconf_info( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  $dump_result = $self->dump_scripts( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  $dump_result = $self->dump_templates( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  $dump_result = $self->dump_disk_config( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  $dump_result = $self->dump_hooks( $release, $classref );
  return( $dump_result ) if( defined $dump_result );

  return( undef, $sections, $customs );
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self      = Argonaut::FAI handle
# $class_str = A space seperated string of classes or arrayref
# $release   = Overwrite or set release provided by $class_str
# $hostname  = Host to use in classlist expansion
# $force     = Ignore cached values and rebuild
#
sub resolve_classlist {
  my( $self, $class_str, $release, $hostname, $force ) = @_;
  my( @classes, @newclasses, $cls_release, $class );

  # Set @classes depending on parameter type
  if( 'ARRAY' eq ref( $class_str ) ) {
    @classes = @{$class_str};
  } else {
    @classes = split( ' ', $class_str );
  }

  # Check for release in classlist
  foreach my $class (@classes) {
    if( ":" eq substr( $class, 0, 1 ) ) {
      return ("Duplicated release in classlist\n")
        if( defined $cls_release );

      if (length(${class}) > 1) {
        $cls_release = substr( $class, 1 );
      } else {
        return( "Invalid release ':' in classlist\n" );
      }
    } else {
      push @newclasses, $class;
    }
  }

  # Overwrite release if supplied
  $cls_release = $release if( defined $release );
  return( "No release for lookup defined\n" )
    if( ! defined $cls_release );

  # Always prepend release
  @classes = @newclasses;
  $class_str = ':' . $cls_release . join( ' ', @classes );

  # Return cached values if not enforced
  if (!(defined $force && $force)) {
    return $self->{ 'RESOLVED' }{ $class_str }
      if( exists $self->{ 'RESOLVED' }{ $class_str } );
  }

  my $ldap = $self->{ 'LDAP' };
  my $base = $self->{ 'base' };

  @newclasses = ();
  my %seen = ( 'LAST' => 1, 'DEFAULT' => 1 );
  $seen{ $hostname } = 1 if( defined $hostname );
  my @faiprofiles = ();
  my( $entry, $mesg );

  # We need to walk through the list of classes and watch out for
  # a profile, which is named like the class. Replace the profile
  # name by the names of the included classes.
  while( 0 != scalar @classes ) {
    $class = shift( @classes );

    # Skip duplicated profiles and classes
    next if( exists $seen{ $class } );

    my $cache = $self->get_class_cache( $cls_release );
    return $cache if( 'HASH' ne ref( $cache ) );

    if( exists $cache->{ 'profiles' } ) {
      if( exists $cache->{ 'profiles' }->{ $class } ) {

        my @profile_classes = @{$cache->{ 'profiles' }->{ $class }{ '_classes' }};

        foreach my $profile_class (reverse @profile_classes) {
          # Check if the class is already in the list?
          next if( exists $seen{ $profile_class } );

          # Prepend class - it may also be a profile
          unshift( @classes, $profile_class )
            if( ! exists $seen{ $profile_class } );
        }

        $seen{ $class } = 1;
      }
    }

    # Just push non-profile classes
    if( ! exists $seen{ $class } ) {
      push( @newclasses, $class );
      $seen{ $class } = 1;
    }
  }

  return( \@newclasses, $cls_release );
}


# - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
#
# $self      = Argonaut::FAI handle
# $class_str = A space seperated string of classes or arrayref
# $hostname  = The non-FQDN hostname
#
# Little convenience function to add standard FAI classes, which are added
# automatically by FAI. These are needed for a correct dump.
#
sub expand_fai_classlist {
  my( $self, $classref, $hostname ) = @_;
  my( @newclasses );

  return undef if( ! defined $classref );

  if( 'ARRAY' eq ref( $classref ) ) {
    @newclasses = @$classref;
  } else {
    @newclasses = split(' ', $classref);
  }

  # These classes are added automatically by FAI...
  unshift( @newclasses, "DEFAULT" );
  push( @newclasses, "${hostname}" ) if( defined $hostname );
  push( @newclasses, "LAST" );

  return \@newclasses if( 'ARRAY' eq ref( $classref ) );
  return join(' ', @newclasses);
}

END {}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
