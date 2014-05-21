package Argonaut::Debconf::Key;

=head1 DESCRIPTION

Abstraction of the complete Debconf key. It is composed of the
question and template part and unifies the interface to
both.

=head1 METHODS

=cut

use warnings;
use strict;

use Data::Dumper qw/Dumper/;

use Argonaut::Debconf::Common   qw/:public/;
use Argonaut::Debconf::Question qw/:public/;
use Argonaut::Debconf::Template qw/:public/;

=head2 new

This is not a Net::LDAP::Class-based object and it has a
custom new() function.

The complete Key is composed of the template and the
question part which are loaded in $$self{template} and
$$self{question} respectively.

Passing any of those as parameters will use the passed
values instead of dispatching additional calls to find
those out.

You can pass in real pointers, or 0 if you plan on
manually adjusting that later before starting to call
the Key's methods. (Or at least those that would need
the part you omitted).

=cut

sub new {
  ( my $s, local %_)= @_;
  my $o= {
    %_,
    question => $_{question}// _question( %_),
    template => $_{template}// _template( %_),
  };

  bless $o, $s
}

=head2 new2

Handy variant of the new() function, figuring things out for you.

Basically just a simple wrapper around new() that calls it with
the correct thing if you pass it an existing Question or Template
to save on making a duplicate call.

=cut

sub new2 {
  ( my $s, local %_)= @_;
  my $ret;

  $_{question} and $_{cn}= $_{question}->cn unless $_{cn};
  $_{template} and $_{cn}= $_{template}->cn unless $_{cn};

  $s->new(
    base_dn  => $_{base_dn}, # May be undef
    cn       => $_{cn},
    question => $_{question},
    template => $_{template}
  )
}


=head2 Accessor functions

A total of 10 accessor functions, 5 for the template, 5 for the
question part of a Key:

Question: template, owners, flags, value, variables

Template: type, description, extendedDescription, default, choices

=cut

sub template            { (shift)->{question}->template( @_)            }
sub owners              { (shift)->{question}->owners( @_)              }
sub flags               { (shift)->{question}->flags( @_)               }
sub value               { (shift)->{question}->value( @_)               }
sub variables           { (shift)->{question}->variables( @_)           }

sub type                { (shift)->{template}->type( @_)                }
sub description         { (shift)->{template}->description( @_)         }
sub extendedDescription { (shift)->{template}->extendedDescription( @_) }
sub default             { (shift)->{template}->default( @_)             }
sub choices             { (shift)->{template}->choices( @_)             }

=head2 cn

The usual LDAP cn attribute; provided here for compatibility with
Net::LDAP::Class-based objects.

=cut

sub cn                  { (shift)->{cn}}

=head2 dn

The usual LDAP dn attribute; provided here for compatibility with
Net::LDAP::Class-based objects.

Note that the DN reported is the DN of the question part; the
template is not that important.

=cut

sub dn                  { (shift)->{question}->dn}


=head1 FUNCTIONS

=head2 _question, _template

Retrieve the question or template part of the Debconf Key.

These are called if the Key's new() call does not contain
pointers to existing objects and are generally not
called manually.

=cut

sub _question {
  my $s= { @_};
  Argonaut::Debconf::Question->find2(
    base_dn => DN( $C->questions_rdn, $$s{base_dn}),
    cn      => $$s{cn},
  )
}

sub _template {
  my $s= { @_};
  Argonaut::Debconf::Template->find2(
    base_dn => DN( $C->templates_rdn, $$s{base_dn}),
    cn      => $$s{cn},
  )
}


=head1 METHODS

=head2 add, remove, set

Convenience methods for setting values on attributes.

You need to pay attention to multi-value/single-avalue
yourself.

Done manually and not via ldap_entry methods as the
LDAP entry pointer is undefined on new objects till
they're saved.

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

=head2 delete, update, create, read_or_create, dump, save

Added for compatibility with Net::LDAP::Class-based
objects.

=cut

sub delete {
  my $s= shift;
  for(qw/template question/) { $$s{$_}->delete if $$s{$_}}
  $s= undef
}

sub update {
  my $s= shift;
  for(qw/template question/) { $$s{$_}->update if $$s{$_}}
}

sub create {
  my $s= shift;
  for(qw/template question/) { $$s{$_}->create if $$s{$_}}
}

sub read_or_create {
  my $s= shift;
  for(qw/template question/) { $$s{$_}->read_or_create if $$s{$_}}
}

sub dump { warn Dumper (shift)}

sub save {
  my $s= shift;

  for(qw/template question/) {
    my $i;
    next unless $i= $$s{$_};

    unless( $i->ldap_entry) {
      warn "Will CREATE $i";
      $i->create;
    } else {
      $i->update
    }
  }
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
