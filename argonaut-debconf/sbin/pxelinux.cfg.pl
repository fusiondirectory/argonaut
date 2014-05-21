#!/usr/bin/perl

=head1 INTRODUCTION

Script that mounts FUSE filesystem on top of the pxelinux.cfg configuration
directory and produces files and file contents based on Debconf keys under
LDAP.

How to run it:

 Remove any previous mounts:
 - sudo fusermount -u /srv/tftp/pxelinux.cfg
 - sudo umount /srv/tftp/pxelinux.cfg

 Start the filesystem:
 - sudo -u tftpd perl -I../lib pxelinux.cfg.pl

(You must start the program under the same user that is running the tftp
daemon, as shown above).

=head1 REFERENCES

https://forge.fusiondirectory.org/projects/debconf/wiki/PXE

=cut

use warnings;
use strict;

use Fuse qw//;
use POSIX qw/ENOENT EINVAL/;
use Net::LDAP qw//;

use Argonaut::Debconf::Init qw/:public/;
use Argonaut::Debconf::Common qw/:public/;

my %c= %{ $C->pxelinux_cfg}; # pxelinux.cfg.pl-specific config

use subs qw/pxeconfigs/;

sub W { warn @_, "\n" if $c{debug}}

# Directory tree. We define just the "/" statically and everything else
# is produced via a lookup into ldap.
my %files= (
  '/'       => {
    type    => 0040,
    mode    => 0755,
    ctime   => time,
    getdir  => \&pxeconfigs,
  },
);

# Run the thing
Fuse::main(
  debug       => $c{debug},
  mountpoint  => $c{mount_point},
  mountopts   => 'nonempty',
  threaded    => 0,
  getattr     => 'main::e_getattr',
  getdir      => 'main::e_getdir',
  open        => 'main::e_open',
  read        => 'main::e_read',
  statfs      => 'main::e_statfs',
);

exit 0;

############################################################
# Helpers below

#
# FUSE filesystem functions
#

sub e_getattr {
  my $file= shift;

  if( $c{dynamic} or not $files{$file}) {
    # We only perform LDAP lookup for something that ends in dd-dd-dd-dd-dd-dd,
    # otherwise it's not a MAC address
    if( $file=~ m#^/((?:\w{2}-)?(?:\w{2}-){5}\w{2})$#) {
      pxeconfigs $1
    }
  }

  my $ref= $files{$file};

  unless( $ref) { return -ENOENT()}

  my @ret= (
    dev(     $file),
    ino(     $file),
    mode(    $file),
    nlink(   $file),
    uid(     $file),
    gid(     $file),
    rdev(    $file),
    size(    $file),
    atime(   $file),
    mtime(   $file),
    ctime(   $file),
    blksize( $file),
    blocks(  $file),
  );
  ( @ret)
}

sub e_getdir {
  my $dir= shift;

  my( @files, $f);
  if( ( $c{dynamic} or not $files{$dir}{content}) and
    ( $f= $files{$dir}{getdir} and ref $f eq 'CODE')) {

    @files= &$f;
    unshift @files, '.';
    $files{$dir}{content}= \@files;
  }

  @{ $files{$dir}{content}}, 0
}

sub e_open { 0}

sub e_read {
  my $file= shift;
  my ($buf, $off) = @_;

  my $ref= $files{$file};

  unless( $ref) {
    return -ENOENT()
  }

  if(not $ref or not exists $$ref{content}) {
    return -EINVAL() if $off> 0
  }

  return -EINVAL() if $off> length $$ref{content};
  return 0 if $off== length $$ref{content};
  substr $$ref{content}, $off, $buf
}

sub e_statfs { return 255, 1, 1, 1, 1, 2}

#
# stat() components
#

sub size( $) {
  my $file= shift;
  my $ref= $files{$file};
  return $$ref{size} if exists $$ref{size};
  return exists $$ref{content} ? length( $$ref{content}) : 0
}
sub mode( $) {
  my $file= shift;
  my $ref= $files{$file};
  return( ( $$ref{type}<<9) + $$ref{mode}) if $ref;
  return 0
}
sub dev( $) {
  my $file= shift;
  0
}
sub ino( $) {
  my $file= shift;
  0
}
sub rdev( $) {
  my $file= shift;
  0
}
sub blocks( $) {
  my $file= shift;
  1
}
sub gid( $) {
  my $file= shift;
  0
}
sub uid( $) {
  my $file= shift;
  0
}
sub nlink( $) {
  my $file= shift;
  1
}
sub blksize( $) {
  my $file= shift;
  1024
}
sub mtime( $) {
  my $file= shift;
  my $ref= $files{$file};
  return $$ref{ctime} if $ref;
  return time
}
sub atime( $) {
  my $file= shift;
  my $ref= $files{$file};
  return $$ref{ctime} if $ref;
  return time
}
sub ctime( $) {
  my $file= shift;
  my $ref= $files{$file};
  return $$ref{ctime} if $ref;
  return time
}

#
# The real work -- retrieving existing PXE devices and producing
# their PXE configs. Note that switching from Net::LDAP to
# Peter Karman's Net::LDAP::Class brought this from 250 down to
# 50 lines.
#

sub pxeconfigs {
  my $filename= shift;
  my %found;

  my @search= ( 'objectClass', 'GOhard');
  my( $mac, $s, $i);

  if( $filename){
    $mac= substr $filename, -17;
    $mac=~ tr/-/:/;
    push @search, 'macAddress', $mac;

    my @sys= ( Argonaut::Debconf::System->find2( @search));
    $i= Net::LDAP::Class::SimpleIterator->new( code => sub { shift @sys});

  } else {
    $i= Net::LDAP::Class::Iterator->new(
      ldap    => $ldap,
      base_dn => $C->ldap_systems_base,
      filter  => AND( join '=', @search), # XXX assumes @search==(a,b)
      class   => 'Argonaut::Debconf::System'
    )
  }

  my @filenames;
  while( $s= $i->next) {
    $mac= $s->macAddress or next;
    $mac=~ s/:/-/g;

    # XXX Retrieving whole config here is expensive, see if we
    # can just pick out the names, retrieve the config later
    # if it is actually requested.
    my $content= $s->PXE;

    # XXX Decide here whether, for hosts with no PXE config, we
    # return empty contents or we don't even include them in
    # the directory listing.
    $content= $content? $content->as_config: '';

    # We show filenames which are macAddress, even though
    # when the PXE requests them, they're in form "01-macAddress".
    # Actually not, let's provide 01- for a change to see how
    # it works in practice.
    my $fn= '01:'. $mac;
    $fn=~ s/:/-/g;
    push @filenames, $fn;

    $files{'/'. $fn}= {
      type    => 0100,
      mode    => 0444,
      ctime   => time,
      content => $content,
      size    => length $content,
    };
  }

  $i->finish;

  ( @filenames)
}

exit 0

__END__
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
