package Argonaut::Debconf::Config;

=head1 DESCRIPTION

Abstraction of the complete Debconf config for a host.

Initialize usually by calling e.g. $p= $system->Config.

=head1 CLASS METHODS

=head2 new( key => value, ...)

Returns complete keys found in the (usually) host tree.

Optional keys to the new() call include iterator,
system and filter.

If the seeAlso config option is enabled, it collects
all questions and templates found in the trees referenced
by the seeAlso pointers. (Depth-based, first match wins
type of scan).

At the end of the seeAlso discovery process, there may be
discrepancies between the existing questions and templates.
Any incomplete entries are ignored and only the
complete keys (those having both parts) are returned.

=cut

use warnings;
use strict;

use Argonaut::Debconf::Common   qw/:public/;
use Argonaut::Debconf::Question qw/:public/;
use Argonaut::Debconf::Template qw/:public/;

sub new {
  ( my $s, local %_)= @_;
  my $o= {
    system => $_{system}
  };

  my $i= $_{iterator};
  unless( $i) {
    $i= Argonaut::Debconf::Tree->new2(
      base_dn => $_{system}->ddn,
      ou => $_{system}->debconfProfile);
    $i and $i= $i->read;
    $i and $i= $i->Keys( filter => $_{filter})
  }
  return unless $i;

  while( $_= $i->next) {
    $$o{keys}{$_->cn}= $_
  }
  $i->finish;

  bless $o, $s
}


=head1 METHODS

=head2 as_preseed_cfg

Return contained config as preseed.cfg-formatted file.

=cut

sub as_preseed_cfg {
  ( my $s, local %_)= @_;
  my @ret;
  for( sort keys %{$$s{keys}}) {
    $_= $$s{keys}{$_};
    push @ret, sprintf "# %s", $_->dn if $_{debug};
    push @ret, join "\t", $_->owners, $_->cn, $_->type, $_->value
  }

  my $ret= join( "\n", @ret). "\n";
  wantarray? ( $ret, scalar @ret) : $ret
}

=head1 METHODS

=head2 as_pxelinux_cfg

Return contained config as pxelinux.cfg-formatted file.

=cut

sub as_pxelinux_cfg {
  ( my $s, local %_)= @_;
  my $append= $$s{system}->gotoKernelParameters;
  $append=~ s/%append/ $s->as_append_line /e;

  my $config= HDOC<<" END";
    PROMPT 0
    TIMEOUT 0
    DEFAULT install
    LABEL install
      kernel ${\( $$s{system}->gotoBootKernel)}
      append $append
  END
}

=head1 METHODS

=head2 as_append_line

Return contained config as a single parameters line
suitable for inserting into the pxelinux "append"
config line.

=cut

sub as_append_line {
  ( my $s, local %_)= @_;
  my @ret;
  for( sort keys %{ $$s{keys}}) {
    $_= $$s{keys}{$_};
    push @ret, $_->cn. '='. $_->value
  }
  join ' ', @ret
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
