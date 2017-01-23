#######################################################################
#
# FusionInventory::Agent::Config::Ldap - get fusioninventory config from ldap
#
# Copyright (C) 2013-2016 FusionDirectory project
#
# Authors: Côme BERNIGAUD
#
#  This program is free software;
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

package FusionInventory::Agent::Config::Ldap;

use strict;
use warnings;

use base qw(FusionInventory::Agent::Config::Backend);

use English qw(-no_match_vars);

use Net::LDAP;

sub new {
    my ($class, %params) = @_;

    my $file =
        $params{file}      ? $params{file}                     :
        $params{directory} ? $params{directory} . '/agent.cfg' :
                            'agent.cfg';

    if ($file) {
        die "non-existing file $file" unless -f $file;
        die "non-readable file $file" unless -r $file;
    } else {
        die "no configuration file";
    }

    my $handle;
    if (!open $handle, q{<}, $file) {
        die "Config: Failed to open $file: $ERRNO";
    }

    while (my $line = <$handle>) {
        $line =~ s/#.+//;
        if ($line =~ /([\w-]+)\s*=\s*(.+)/) {
            my $key = $1;
            my $value = $2;

            # remove the quotes
            $value =~ s/\s+$//;
            $value =~ s/^'(.*)'$/$1/;
            $value =~ s/^"(.*)"$/$1/;

            if ($key =~ m/^ldap_(.*)$/) {
              $params{$1} = $value;
            }
        }
    }
    close $handle;

    die "Missing parameter uri" unless $params{uri};
    die "Missing parameter ip"  unless $params{ip};

    my $self = {
        uri => $params{uri},
        ip  => $params{ip}
    };

    if ($params{base}) {
      $self->{base}   = $params{base};
    } else {
      $self->{uri}  =~ m|^(ldap://[^/]+)/([^/]+)$| or die "Missing ldap base";
      $self->{base} = $2;
      $self->{uri}  = $1;
    }

    $self->{bind_dn}   = $params{bind_dn}  if $params{bind_dn};
    $self->{bind_pwd}  = $params{bind_pwd} if $params{bind_pwd};

    bless $self, $class;

    return $self;
}

sub getValues {
    my ($self) = @_;

    my $ldap = Net::LDAP->new( $self->{uri} );
    if ( ! defined $ldap ) {
        warn "LDAP 'new' error: '$@' with uri '".$self->{uri}."'";
        return;
    }

    my $mesg;
    if( defined $self->{bind_dn} ) {
        if( defined $self->{bind_pwd} ) {
            $mesg = $ldap->bind( $self->{bind_dn}, password => $self->{bind_pwd} );
        } else {
            $mesg = $ldap->bind( $self->{bind_dn} );
        }
    } else {
        $mesg = $ldap->bind();
    }

    if ( $mesg->code != 0 ) {
        warn "LDAP bind error: ".$mesg->error." (".$mesg->code.")";
        return;
    }

    my %values;
    my %params =
    (
      'server'                  => 'fiAgentServer',
      'local'                   => 'fiAgentLocal',
      'delaytime'               => 'fiAgentDelaytime',
      'wait'                    => 'fiAgentWait',
      'lazy'                    => 'fiAgentLazy',
      'stdout'                  => 'fiAgentStdout',
      'no-task'                 => 'fiAgentNoTask',
      'scan-homedirs'           => 'fiAgentScanHomedirs',
      'html'                    => 'fiAgentHtml',
      'backend-collect-timeout' => 'fiAgentBackendCollectTimeout',
      'force'                   => 'fiAgentForce',
      'tag'                     => 'fiAgentTag',
      'additional-content'      => 'fiAgentAdditionalContent',
      'no-p2p'                  => 'fiAgentNoP2p',
      'proxy'                   => 'fiAgentProxy',
      'user'                    => 'fiAgentUser',
      'password'                => 'fiAgentPassword',
      'ca-cert-dir'             => 'fiAgentCaCertDir',
      'ca-cert-file'            => 'fiAgentCaCertFile',
      'no-ssl-check'            => 'fiAgentNoSslCheck',
      'timeout'                 => 'fiAgentTimeout',
      'no-httpd'                => 'fiAgentNoHttpd',
      'httpd-ip'                => 'fiAgentHttpdIp',
      'httpd-port'              => 'fiAgentHttpdPort',
      'httpd-trust'             => 'fiAgentHttpdTrust',
      'logger'                  => 'fiAgentLogger',
      'logfile'                 => 'fiAgentLogfile',
      'logfile-maxsize'         => 'fiAgentLogfileMaxsize',
      'logfacility'             => 'fiAgentLogfacility',
      'color'                   => 'fiAgentColor',
      'daemon'                  => 'fiAgentDaemon',
      'no-fork'                 => 'fiAgentNoFork',
      'debug'                   => 'fiAgentDebug',
    );
    my @booleans =
    (
      'no-httpd',
      'no-fork',
      'no-p2p',
      'daemon'
    );

    $mesg = $ldap->search(
        base   => $self->{base},
        filter => "(&(objectClass=fusionInventoryAgent)(ipHostNumber=".$self->{ip}."))",
        attrs => [values(%params)]
    );

    if(scalar($mesg->entries)==1) {
        while (my ($key,$value) = each(%params)) {
            if (($mesg->entries)[0]->exists("$value")) {
                if (grep {$_ eq $key} @booleans) {
                    $values{"$key"} = ($mesg->entries)[0]->get_value("$value") eq "TRUE" ? 1 : undef;
                } else {
                    $values{"$key"} = ($mesg->entries)[0]->get_value("$value");
                }
            } else {
                if (not (grep {$_ eq $key} @booleans)) {
                    $values{"$key"} = "";
                }
            }
        }
        return %values;
    } elsif(scalar($mesg->entries)==0) {
        $mesg = $ldap->search( # perform a search
                    base   => $self->{base},
                    filter => "ipHostNumber=".$self->{ip},
                    attrs => [ 'dn' ]
                );
        if (scalar($mesg->entries)>1) {
            warn "Several computers are associated to IP ".$self->{ip}.".";
            return;
        } elsif (scalar($mesg->entries)<1) {
            warn "There is no computer associated to IP ".$self->{ip}.".";
            return;
        }
        my $dn = ($mesg->entries)[0]->dn();
        my $mesg = $ldap->search( # perform a search
            base    => $self->{base},
            filter  => "(&(objectClass=fusionInventoryAgent)(member=$dn))",
            attrs   => [values(%params)]
        );
        if(scalar($mesg->entries)==1) {
            while (my ($key,$value) = each(%params)) {
                if (($mesg->entries)[0]->get_value("$value")) {
                    if (grep {$_ eq $key} @booleans) {
                        $values{"$key"} = ($mesg->entries)[0]->get_value("$value") eq "TRUE" ? 1 : undef;
                    } else {
                        $values{"$key"} = ($mesg->entries)[0]->get_value("$value");
                    }
                } else {
                    if (not (grep {$_ eq $key} @booleans)) {
                        $values{"$key"} = "";
                    }
                }
            }
            return %values;
        } else {
            warn "This computer (".$self->{ip}.") is not configured in LDAP to run this module (missing service fusionInventoryAgent).";
            return;
        }
    } else {
        warn "Several computers are associated to IP ".$self->{ip}.".";
        return;
    }
}

1;
__END__

=head1 NAME

FusionInventory::Agent::Config::LDAP - LDAP-based configuration backend

=head1 DESCRIPTION

This is a FusionInventory LDAP configuration backend.

=head1 BUGS

Please report any bugs, or post any suggestions, to the fusiondirectory mailing list fusiondirectory-users or to
<https://forge.fusiondirectory.org/projects/argonaut-agents/issues/new>

=head1 LICENCE AND COPYRIGHT

This code is part of Argonaut Project <https://www.argonaut-project.org/>

=over 5

=item Copyright (C) 2013-2016 FusionDirectory project

=back

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
