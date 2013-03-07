package Argonaut::Debconf::Tree;

=head1 DESCRIPTION

Abstraction of the ou=debconf,cn=NAME,ou=TYPE,ou=systems
entry in the FusionDirectory LDAP layout.

This has been abstracted primarily for being able to
look into the entry itself and retrieve its seeAlso
pointers.

=head1 METHODS

=cut

use warnings;
use strict;

use Net::LDAP::Class::Iterator qw//;

use Argonaut::Debconf::Common qw/:public/;

use base qw/Argonaut::Debconf::Class/;

sub _init {
	__PACKAGE__->metadata->setup(
		attributes          => [qw/
			ou seeAlso
		/],

		unique_attributes   => [qw/
			ou
		/],

		base_dn             => $C->ldap_base,
	)
}


=head2 Questions, Templates

Return iterator to the questions or templates part of a toplevel
Debconf tree.

These functions are not "recursive" and do not concern themselves
with seeAlso pointers. They return data as seen in the tree
specified.

=cut

sub Questions {
	( my $s, local %_)= @_;
	$s->Entries( %_, base_dn => $s->qdn, class => 'Argonaut::Debconf::Question');
}

sub Templates {
  ( my $s, local %_)= @_;
	$s->Entries( %_, base_dn => $s->tdn, class => 'Argonaut::Debconf::Template');
}

sub Entries {
  ( my $s, local %_)= @_;
	Net::LDAP::Class::Iterator->new(
		ldap    => $ldap,
		base_dn => $_{base_dn},
		filter  => AND( '(objectClass=debConfDbEntry)', $_{filter}),
		class   => $_{class},
	)
}


=head2 ddn, qdn, tdn

The usual debconf, questions, templates RDN parts.

=cut


sub ddn { (shift)->dn }
sub qdn { DN $C->questions_rdn, (shift)->dn }
sub tdn { DN $C->templates_rdn, (shift)->dn }


=head2 Keys

Return the contained questions as iterator on
complete Debconf Keys.

This may include traveling the tree hierarchically,
depending on the state of the 'seeAlso' configuration
setting and any actual seeAlsos defined.

When all of the paths have been traveled, only the keys
with both the question and template part are returned.

=cut

sub Keys {
  ( my $s, local %_)= @_;
	my @trees= ( $s );
	my( %q, %t);;
	$$s{keys}= [];

	for( my $i= 0; $i< @trees; $i++) {
		my $t= $trees[$i];

		my $qi= $t->Questions( %_);
		while( my $qc= $qi->next) { $q{$qc->cn}//= $qc}
		my $ti= $t->Templates;
		while( my $tc= $ti->next) { $t{$tc->cn}//= $tc}

		if( $C->seeAlso) {
			my @sa= $t->seeAlso;
			for( @sa) { $_= __PACKAGE__->read1( base_dn => $_)}
			if( @sa) { splice @trees, $i+ 1, 0, @sa}
		}
	}

	for my $k( sort keys %q) {
		my $v= $q{$k};

		if( $t{$k}) {
			push @{ $$s{keys} }, Argonaut::Debconf::Key->new2(
				cn       => $k,
				question => $q{$k},
				template => $t{$k},
			)
		}
	}

	Net::LDAP::Class::SimpleIterator->new(
		code => sub { shift @{ $$s{keys}}}
	)
}



=head1 CLASS METHODS

=head2 DESTROY

Defined only to terminate any iterators in progress
and eliminate runtime warnings.

=cut

sub DESTROY {
	my $s= shift;
	$$s{qi}->finish if $$s{qi}
}

1

__END__
=head1 REFERENCES

=head1 AUTHORS

SPINLOCK - Advanced GNU/Linux networks in commercial and education sectors.

Copyright 2011, Davor Ocelic <docelic@spinlocksolutions.com>

Copyright 2011, SPINLOCK Solutions,
  http://www.spinlocksolutions.com/,
  http://techpubs.spinlocksolutions.com/

=head1 LICENSE

GNU GPL v3 or later. http://www.gnu.org/licenses/gpl.html

=cut
