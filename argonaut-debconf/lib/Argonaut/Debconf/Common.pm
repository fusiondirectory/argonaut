package Argonaut::Debconf::Common;

=head1 DESCRIPTION

Abstraction of the module config object, definition of
shared objects and the common procedural functions.

=cut

use warnings;
use strict;

use Argonaut::Debconf::Setup qw/%config/;

use Net::LDAP qw//;

use base qw/Exporter/;

my @EXPORT_INTERNAL= qw//;
my @EXPORT_PUBLIC= qw/$C $ldap $mesg &DN &ND &AND &HDOC/;

our @EXPORT_OK= ( @EXPORT_INTERNAL, @EXPORT_PUBLIC);
our %EXPORT_TAGS= (
  internal  => [ @EXPORT_INTERNAL ],
  public    => [ @EXPORT_PUBLIC ],
  all       => [ @EXPORT_INTERNAL, @EXPORT_PUBLIC ],
);

our( $C, $ldap, $mesg);

$C= __PACKAGE__->new;

=head1 CLASS METHODS

=head2 new

The usual constructor. It creates a config object
with hash read from Argonaut::Debconf::Setup.

All the options are callable both through $$object{option}
and $object->option.

=cut

sub new {
  my $s= bless { %config}, (shift);

  for( keys %config) {
    eval "sub $_ { (shift)->{$_}}"
  }

  $s
}

=head1 METHODS

=head2 _init

LDAP connection init function. Usually called only
by init_config(), hence the "_" prefix.

=cut

sub _init {
  $ldap= Net::LDAP->new( $C->ldap_host);
  $mesg= $ldap->bind(
    $C->ldap_binddn,
    password    => $C->ldap_bindpw,
    scheme      => $C->ldap_scheme,
    timeout     => $C->ldap_timeout,
    protocol    => $C->ldap_protocol,
    onerror     => $C->ldap_onerror,
    raw         => $C->ldap_raw,
  );
  shift
}

=head2 init_config

Main init function. Call as the first command in
your program.

This is already taken care of for you if you
"use Argonaut::Debconf::Init".

All the relevant initialization work has been
split out to non-immediate init() functions so that
you could call e.g. perl -c on the files without
automatically triggering LDAP connections.

=cut

sub init_config {
  $C->_init;
  Argonaut::Debconf::Question->_init;
  Argonaut::Debconf::Template->_init;
  Argonaut::Debconf::System->_init;
  Argonaut::Debconf::Tree->_init;
}

=head1 FUNCTIONS

=head2 DN( components), ND( components), AND( filter atoms)

Quick helper functions for concatenating LDAP DNs.

ND() is the "reverse DN()", i.e. it works on the reverse()
of the arguments passed to it.

=cut

sub DN { join ',', @_}
sub ND { join ',', reverse @_}
sub AND{
  @_ = grep { $_} @_;
  for( @_) { $_ = '('. $_ . ')' if substr( $_, 0, 1) ne '('}
  '(&'. ( join '', @_). ')';
}

=head2 HDOC

A heredoc formatter allowing for indented heredocs.
It derives the indent character and its amount based on the
first line of body.

Use as e.g.:

  my $config= HDOC<<"  END";
  Heredoc, with 2 spaces as the front removed on this and
    all subsequent lines. The further 2 spaces on this line will
    be preserved.
  END

=cut

sub HDOC {
  my $howmany= shift if @_> 1;
  my $body= shift;
  my $what= substr $body, 0, 1;
  $body=~ s/^($what+)/ $howmany= length $1 unless $howmany; '' /me;
  $body=~ s/^${what}{$howmany}//gm;
  $body
}

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
