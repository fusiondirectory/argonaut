#!/usr/bin/perl
#
# Copyright (C) 2011 Davor Ocelic <docelic@spinlocksolutions.com>.
#                    Spinlock Solutions, http://www.spinlocksolutions.com/

=head1 NAME

Debconf::DbDriver::FusionDirectory - access Debconf database in an LDAP directory

This is a Net::LDAP::Class-based implementation of the LDAP driver.

It is an alternative driver to the existing Debconf LDAP backend, containing
more features and being production-ready.

To run it, you need the FusionDirectory Debconf Plugin support files,
after which the definition in /etc/debconf.conf is as simple as e.g.:

Name: configdb
Driver: FusionDirectory

Name: templatedb
Driver: FusionDirectory

If you are installing in a chroot or temporary environment where the
machine does not have its real IP, specify it with the Ip: option.

It can be used standalone, but best results are achieved in combination
with FusionDirectory (http://www.fusiondirectory.org).

=cut

package Debconf::DbDriver::FusionDirectory;
use warnings;
use strict;
use Debconf::Log qw(:all);
use Data::Dumper qw/Dumper/;
use lib '/root/debconf-plugin/lib';
use FusionDirectory::Plugin::Debconf::Init qw//;
use FusionDirectory::Plugin::Debconf::System qw/:public/;
use base 'Debconf::DbDriver';
use fields qw(ip group);
use fields qw(items system variables);

sub W {} # warn @_}

=head1 CLASS METHODS

=head2 new( name => ..., [group => ...])

The usual new() method. Name is the database name as specified
in the config file.

We need to know whether we are initialized to scoop questions
or templates, so optional "Group: questions/templates" can be
specified in the config file.

If unspecified, we try to determine that from the database
name.

=cut

sub new {
	my( $s, %p)= @_;

	unless( $p{group}) {
		if( $p{name}=~ /temp/i)          { $p{group}= 'templates'}
		elsif( $p{name}=~ /conf|ques/i)  { $p{group}= 'questions'}
		else {
			die "Need Group: in debconf.conf, can't determine it from '$p{name}'.\n"
		}
	}

	$s->SUPER::new( %p)
}

=head2 init

Look up the machine in the LDAP directory (based on IP as
returned by Net::Address::IP::Local->public) and retrieve
its complete config.

=cut

sub init {
	my $s= shift;

	unless( $$s{ip}) {
		require 'Net::Address::IP::Local';
		$$s{ip}= Net::Address::IP::Local->public;
	}

	$ip or die "Need Ip: in debconf.conf, unable to determine it.\n"

	$$s{system}= FusionDirectory::Plugin::Debconf::System
		->new2( ipHostNumber => $ip)
		->read;

		my $i= $$s{system}->${\( ucfirst $$s{group} )};

		while( my $e= $i->next) { $$s{items}{$e->cn}= $e}
}

=head1 METHODS

=head2 exists( item)

This method returns one of three values:

true  -- yes, it's in the cache
undef -- marked as deleted in the cache, so does not exist (XXX not implemented)
0     -- not in the cache; up to derived class now

=cut

sub exists {
	my( $s, $item)= @_;
	exists( $$s{items}{$item})|| 0
}

=head2 addowner( item, owner, type)

Add an owner, if the underlying db is not readonly, and if the given
type is acceptable.

Creates a new item if it doesn't exist yet.

=cut

sub addowner {
  my( $s, $item, $owner, $type)= @_;

  return if $s->{readonly};

  unless( $$s{items}{$item}) {
    return if not $s->accept( $item, $type);
    debug "db $s->{name}" => "creating $item";

    my( $class, $method);
    if( $$s{group} eq 'questions') {
      ( $class, $method)= (
        'FusionDirectory::Plugin::Debconf::Question', 'qdn');
    } else {
      ( $class, $method)= (
        'FusionDirectory::Plugin::Debconf::Template', 'tdn');
    }

    $$s{items}{$item}= $class->new2(
      base_dn  => $$s{system}->$method,
      cn       => $item);
  }

  my $i= $$s{items}{$item};

  $i->add( 'owners', $owner);

  $owner
}

sub removeowner {
  my( $s, $item, $owner)= @_;

  return if $s->{readonly};

  my $i;
  return unless $i= $$s{items}{$item};

  $i->remove( 'owners', $owner);

  $owner
}

sub owners {
  my( $s, $item)= @_;

  return if $s->{readonly};

  my $i;
  return unless $i= $$s{items}{$item};

  $i->owners
}

=head2 getfield( item, field)

Retrieve value of a field.

Note that Debconf gives Questions benefit of the doubt, so all of the
usual template fields (default, description, extendedDescription,
type and choices) will first be checked if they exist in the question
before they're looked up in the template.

Nice to know for convenient overriding purposes.

=cut

sub getfield {
  my( $s, $item, $field)= @_;
  my $i;
  return unless $i= $$s{items}{$item};
  return unless grep { $_ eq $field } @{ $i->metadata->attributes};
  $i->$field
}

=head2 setfield( item, field, value)

Set value of a field, if the database is not read-only.

=cut

sub setfield {
  my( $s, $item, $field, $value)= @_;
  return if $s->{readonly};
  my $i;
  return unless $i= $$s{items}{$item};
  return unless grep { $_ eq $field } @{ $i->metadata->attributes};
  $i->$field( $value)
}

sub removefield {
  my( $s, $item, $field)= @_;
  return if $s->{readonly};
  my $i;
  return unless $i= $$s{items}{$item};
  $i->set( $field)
}

sub fields {
  my( $s, $item)= @_;
  my $i;
  return unless $i= $$s{items}{$item};
  @{ $i->metadata->attributes};
}

sub getflag {
  my( $s, $item, $flag)= @_;
  my $i;
  return unless $i= $$s{items}{$item};
  return 'true' if grep { $_ and $_ eq $flag } $i->flags;
  'false'
}

=head2 setflag( item, flag, value)

Sets the flag if the underlying DB is not readonly.

=cut

sub setflag {
  my( $s, $item, $flag, $value)= @_;
  W 'setflag', @_;

  return if $s->{readonly};
  my $i;
  return unless $i= $$s{items}{$item};

  if( $value eq 'true') {
    $i->add( 'flags', $flag)
  } else {
    $i->remove( 'flags', $flag)
  }

  $value
}

sub flags {
  my( $s, $item)= @_;
  return if $s->{readonly};
  my $i;
  return unless $i= $$s{items}{$item};
  $i->flags
}

=head2 variables( item)

Return names of the variables defined.

=cut

sub getvariable {
  W 'getvariable', @_;
  die "IMPLEMENT!";
}


sub setvariable {
  W 'setvariable', @_;
  die "IMPLEMENT!";
}

sub variables {
  my( $s, $item)= @_;
  my $v;
  return unless $v= $$s{variables}{$item};
  return keys %$v;
}

=head2 shutdown

Saves to the underlying database.

Returns true unless any of the operations fail.

=cut

sub shutdown {
	my $s= shift;
	W 'SHUTDOWN';
	
	return if $s->{readonly};

	my $c= $$s{items};

	while( my( $k, $v)= each %$c) {
		$v->save
	}

	1
}

sub iterator {
	my( $s, $si)= @_;

	my @items= keys %{$$s{items}};

	my $i= Debconf::Iterator->new(callback => sub {
		while( my $item= pop @items) {
			next unless defined $$s{items}{$item};
			return $item
		}
		return unless $si;

		my $ret;
		do { $ret= $si->iterate } while
			defined $ret and exists $$s{items}{$ret};

		return $ret
	});

	$i
}

1
