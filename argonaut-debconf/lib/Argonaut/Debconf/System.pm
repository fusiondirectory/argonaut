package Argonaut::Debconf::System;

=head1 DESCRIPTION

Abstraction of a manageable system, i.e. the entries found under
cn=NAME,ou=TYPE,ou=systems in the FusionDirectory LDAP layout.

=cut

use warnings;
use strict;

use Argonaut::Debconf::Tree;

use base qw/Argonaut::Debconf::Class/;

use Argonaut::Debconf::Common qw/:public/;

sub _init {
  __PACKAGE__->metadata->setup(
      attributes          => [qw/
        cn description
        objectClass
        gotoBootKernel gotoKernelParameters gotoMode
        ipHostNumber macAddress debconfProfile
      /],

      unique_attributes   => [qw/
        cn ipHostNumber macAddress
      /],

      base_dn             => $C->ldap_base,
  );
}

=head1 METHODS

=head2 ddn, qdn, tdn

The debconf, questions and templates relative DN parts.

They're constructed from the Setup values of debconf_rdn,
questions_rdn and templates_rdn.

=cut

sub ddn {
  my $system = shift;
  DN "ou=".$system->debconfProfile, $C->debconf_rdn, $system->base_dn
}
sub qdn {
  my $system = shift;
  DN $C->questions_rdn, $system->ddn()
}
sub tdn {
  my $system = shift;
  DN $C->templates_rdn, $system->ddn()
}


=head2 Questions, Templates

Iterators to the hosts Debconf Questions and Templates, respectively.

=cut

sub Questions   { (shift)->Tree->Questions( @_)}
sub Templates   { (shift)->Tree->Templates( @_)}


=head2 Tree, Preseed, PXE, Config

Convenience functions for instantiating the listed objects
for on the existing system.

=cut

sub Tree {
  ( my $s, local %_)= @_;
  Argonaut::Debconf::Tree->new2(
    base_dn => $s->ddn,
    ou      => 'debconf',
    %_)->read
}

sub Preseed {
  ( my $s, local %_)= @_;
  Argonaut::Debconf::Preseed->new( system => $s, %_)
}

sub PXE {
  ( my $s, local %_)= @_;
  Argonaut::Debconf::PXE->new( system => $s, %_)
}

sub Config {
  ( my $s, local %_)= @_;
  Argonaut::Debconf::Config->new( system => $s, %_)
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
