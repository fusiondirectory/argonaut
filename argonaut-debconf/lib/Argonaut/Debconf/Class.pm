package Argonaut::Debconf::Class;

=head1 DESCRIPTION

Subclass of the basic Net::LDAP::Class, defined here so
we can conveniently extend the base class with useful,
common methods.

=cut

use warnings;
use strict;

use base qw/Net::LDAP::Class/;

use Argonaut::Debconf::Common qw/:public/;

=head1 FUNCTIONS

=head2 find1( key => value, ...)

Retrieve Net::LDAP::Entry reference to the specific DN
requested. The parameters are passed directly onto
the LDAP search() function, meaning you'll want to
provide at least 'base', 'scope' and 'filter', and
eventually 'attrs'.

=cut

sub find1 { ( ($mesg= $ldap->search( @_))->entries)[0]}

=head1 CLASS METHODS

=head2 read1( key => value, ...)

Retrieve the appropriate Net::LDAP::Class-based object
requested. The parameters are passed directly onto
the LDAP search() function, meaning you'll want to
provide at least the base_dn to retrieve. Filter is
'*' and scope is 'base' by default.

=cut

sub read1 {
  ( my $s, local %_)= @_;
  ($s->find(
    ldap    => $ldap,
    base_dn => $_{base_dn},
    scope   => 'base',
    filter  => 'objectClass=*',
    %_))[0]
}

=head2 new2( key => value, ...)

Generic function providing the necessary parameters to
the new() functions automatically and passing other
arguments intact.

=cut

sub new2 { (shift)->new( ldap => $ldap, @_)}

=head2 find2

Finds the LDAP entry and casts it to the appropriate
Net::LDAP::Class subclass based on the unique attributes.

If the unique object is not found under the specified
tree, the method checks for any seeAlsos defined on it
and repeats the search under the pointed trees til the
first match is found.

This extended search functionality can be turned off
by setting the 'seeAlso' config value to false.

This function is currently used only when a specific
Key object is searched and the plugin is traversing
the entries to find the question and the template part
and to return them as a complete Key.

XXX - When Tree object is passed, modify the function
to recognize it and retrieve seeAlso from it instead
of calling find1().

=cut

sub find2 {
  ( my $s, local %_)= @_;
  my @seeAlso= ( $_{base_dn});
  for( @seeAlso) {
    $_{base_dn}= $_;

    # $ret is Net::LDAP::Class-based object here, if found.
    # Don't let find1 fool you; it's used only for traversing
    # the seeAlsos.
    my $ret= $s->new( ldap => $ldap, %_)->read;
    return $ret if $ret or not $C->seeAlso;

    if( my $e= find1(
      base  => $_,
      scope => 'base',
      filter=> '(objectClass=*)', #organizationalUnit)',
      attrs => 'seeAlso',
    )) {
      my @sa= ( $e->get_value( 'seeAlso'));
      push @seeAlso, @sa if @sa
    }
  }
}

=head2 dn

Generic method to return DN of any Net::LDAP::Class-based
object.

=cut

sub dn    { (shift)->ldap_entry->dn}


=head2 add( attr => value), remove( attr => value), set( attr, values)

Convenience methods for managing values on attributes.

You need to pay attention to multi-value/single-value
yourself.

Done manually and not via ldap_entry methods as the
LDAP entry pointer is undefined on newly created
objects.

These methods compare what you give them to existing
values; only the actual state changes matter with add()
and remove().

=cut

sub add {
  my( $s, $a, $v)= @_;
  my @o= $s->$a// ();
  if( not @o or not grep { $_ eq $v } @o) { push @o, $v}
  $s->set( $a, @o);
  @o
}

sub remove {
  my( $s, $a, $v)= @_;
  my @o= $s->$a// ();
  my @n= @o ? grep { $_ ne $v } @o : ();
  if( @o and @n< @o) { $s->set( $a, @n)}
  @n
}

sub set {
  my( $s, $a, @v)= @_;
  $s->$a( @v > 1 ? [ @v]: @v);
  @v
}


=head2 action_for_update, action_for_create

Generic actions that cut the story short and do the job.

XXX - Extend this to recognize real value changes. Currently,
the way the original function works is it schedules the entry's
attributes for modification even if they're set to the value
they already have.

=cut

sub action_for_update {
  my $s= shift;
  $s->ldap_entry->update( $ldap);
  return
}

sub action_for_create {
  my $s= shift;

  my $e= Net::LDAP::Entry->new(
    DN( 'cn='. $$s{_not_yet_set}{cn}, $$s{base_dn}), # DN
    objectClass => [qw/top debConfDbEntry/],         #
    %{ $$s{_not_yet_set}}                            # Attrs
  );

  $mesg= $e->update( $ldap);
  $mesg->code and warn $mesg->error;
  return
}

1

__END__
=head1 REFERENCES

=head1 AUTHORS

SPINLOCK - Advanced GNU/Linux networks in commercial and education sectors.

Copyright (C) 2011, Davor Ocelic <docelic@spinlocksolutions.com>
Copyright (C) 2011-2013 FusionDirectory project

Copyright (C) 2011, SPINLOCK Solutions,
  http://www.spinlocksolutions.com/,
  http://techpubs.spinlocksolutions.com/

=head1 LICENSE

GNU GPL v3 or later. http://www.gnu.org/licenses/gpl.html

=cut
