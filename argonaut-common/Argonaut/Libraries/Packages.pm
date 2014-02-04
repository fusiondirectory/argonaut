#######################################################################
#
# Argonaut::Libraries::Packages -- get and parse Debian Packages.
#
# Copyright (C) 2011-2013 FusionDirectory project
#
# Author: Côme BERNIGAUD
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>
#
#######################################################################

package Argonaut::Libraries::Packages;

use strict;
use warnings;

use 5.008;

use MIME::Base64;
use Path::Class;
use Net::LDAP;
use Config::IniFiles;
use File::Path;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use LWP::Simple;

use Argonaut::Libraries::Common qw(:ldap);

BEGIN
{
  use Exporter ();
  use vars qw(@EXPORT_OK @ISA $VERSION);
  $VERSION = '2011-04-11';
  @ISA = qw(Exporter);

  @EXPORT_OK = qw(get_repolines get_packages_info store_packages_file cleanup_and_extract);
}

my $configfile = "/etc/argonaut/argonaut.conf";

=pod
=item get_repolines
Get repolines from ldap

=cut
sub get_repolines {
    my ($mac,$cn) = @_;

    my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);
    my $ldap_configfile        =   $config->val( ldap => "config"                  ,"/etc/ldap/ldap.conf");
    my $ldap_dn                =   $config->val( ldap => "dn"                      ,"");
    my $ldap_password          =   $config->val( ldap => "password"                ,"");

    my $ldapinfos = argonaut_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);

    if ( $ldapinfos->{'ERROR'} > 0) {
      print ( $ldapinfos->{'ERRORMSG'}."\n" );
      exit ($ldapinfos->{'ERROR'});
    }

    my $ldap = $ldapinfos->{'HANDLE'};
    my $ldap_base = $ldapinfos->{'BASE'};

    my $mesg;

    if(defined $mac) {
        $mesg = $ldap->search(
            base => $ldap_base,
            filter => "(&(objectClass=FAIrepositoryServer)(macAddress=$mac))",
            attrs => [ 'FAIrepository' ] );
    } elsif(defined $cn) {
        $mesg = $ldap->search(
            base => $ldap_base,
            filter => "(&(objectClass=FAIrepositoryServer)(cn=$cn))",
            attrs => [ 'FAIrepository' ] );
    } else {
        $mesg = $ldap->search(
            base => $ldap_base,
            filter => "(&(objectClass=FAIrepositoryServer))",
            attrs => [ 'FAIrepository' ] );
    }

    $mesg->code && die "Error while searching repositories :".$mesg->error;

    $ldap->unbind();

    my @repolines = ();
    foreach my $entry ($mesg->entries()) {
      foreach my $repoline ($entry->get_value('FAIrepository')) {
        my ($uri,$parent,$dist,$sections,$install,$local,$archs) = split('\|',$repoline);
        my $sections_array = [split(',',$sections)];
        if ($install eq 'update') {
          foreach my $section (@$sections_array) {
            if ($section !~ m/^updates/) {
              $section = "updates/$section";
            }
          }
        }
        my $repo = {
          'line'        => $repoline,
          'uri'         => $uri,
          'parent'      => $parent,
          'dist'        => $dist,
          'sections'    => $sections_array,
          'installrepo' => $install,
          'localmirror' => ($local eq "local"),
          'archs'       => [split(',',$archs)]
        };
        push @repolines, $repo;
      }
    }

    return @repolines;
}


=item get_packages_info
Get packages list with all requested attrs.
Uses the Packages file from the server for that.
If no mac is provided, all servers (for the specified release) in the ldap are checked.

=cut
sub get_packages_info {
    my ($packages_folder,$mac,$release,$attrs,$filters,$from,$to) = @_;

    if((defined $from) && ($from < 0)) {
        undef $from;
    }
    if((defined $to) && ($to < 0)) {
        undef $to;
    }
    my @filters_temp = grep { $_ ne '' } @{$filters};
    if(@filters_temp) {
        $filters = \@filters_temp;
    } else {
        undef $filters;
    }

    push @{$attrs},'PACKAGE' if (not (grep {uc($_) eq 'PACKAGE'} @{$attrs}));
    #~ push @{$attrs},'VERSION' if (not (grep {uc($_) eq 'VERSION'} @{$attrs}));

    my @repolines = get_repolines($mac);

    my $package_indice = 0;
    my $distributions = {};
    mkpath($packages_folder);
    foreach my $repo (@repolines) {
        my $dist = $repo->{'dist'};
        my $uri = $repo->{'uri'};
        my $localuri = $uri;
        $localuri =~ s/^http:\/\///;
        if(defined($release) && ($dist ne $release)) {
            next;
        }

        my $localmirror = $repo->{'localmirror'};
        if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
            push @{$attrs},'FILENAME' if (not (grep {uc($_) eq 'FILENAME'} @{$attrs}));
        }

        foreach my $section (@{$repo->{'sections'}}) {
            if(!defined $distributions->{"$dist/$section"}) {
                $distributions->{"$dist/$section"} = {};
            }
            my $packages = $distributions->{"$dist/$section"};
            foreach my $arch (@{$repo->{'archs'}}) {
                my $packages_file = "$packages_folder/$localuri/dists/$dist/$section/binary-$arch/Packages";
                open (PACKAGES, "<$packages_file") or next;
                my $parsed = {};
                while (<PACKAGES>) {
                    if (/^$/) {
                        # Empty line means this package info lines are over
                        $package_indice++;
                        if((! defined $from) || ($package_indice>$from)) {
                            if($localmirror) {
                                # If it's a local mirror, it's supposed to run the debconf crawler and have the template extracted
                                # So we just download it (if it's not there, we assume there is no template for this package)
                                if (grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                                    my $template = get("$uri/debconf.d/$dist/$section/".$parsed->{'PACKAGE'});
                                    if(defined $template) {
                                        $parsed->{'HASTEMPLATE'} = 1;
                                        $parsed->{'TEMPLATE'} = $template;
                                    }
                                } elsif (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}) {
                                    if(head("$uri/debconf.d/$dist/$section/".$parsed->{'PACKAGE'})) {
                                        $parsed->{'HASTEMPLATE'} = 1;
                                    }
                                }
                            } else {
                                # If it's not a local mirror, we just download the package, we'll extract the template later
                                if ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs})) {
                                    my $filedir = $parsed->{'FILENAME'};
                                    $filedir =~ s/[^\/]+$//;
                                    mkpath($packages_folder."/".$filedir);
                                    mirror("$uri/".$parsed->{'FILENAME'},$packages_folder."/".$parsed->{'FILENAME'});
                                }
                            }
                            $packages->{$parsed->{'PACKAGE'}} = $parsed;
                        }
                        $parsed = {};
                        if((! defined $to) || ($package_indice<$to)) {
                            next;
                        } else {
                            last;
                        }
                    }
                    if (my ($key, $value) = m/^(.*): (.*)/) {
                        if((defined $filters) && (uc($key) eq "PACKAGE")) {
                            my $match = 0;
                            foreach my $filter (@{$filters}) {
                                if($value =~ /$filter/) {
                                    $match = 1;
                                    last;
                                }
                            }
                            if($match == 0) {
                                while(<PACKAGES>) {
                                    if (/^$/) {
                                        last;
                                    }
                                }
                                $parsed = {};
                                next;
                            }
                        }
                        if (grep {uc($_) eq uc($key)} @{$attrs}) {
                            if (uc($key) eq 'DESCRIPTION') {
                                $parsed->{'DESCRIPTION'} = encode_base64($value);
                            } elsif ((uc($key) eq 'PACKAGE') && (defined $packages->{$value}) && !(grep {uc($_) eq 'VERSION'} @{$attrs})) {
                                # We already have the info on this package and version was not asked, skip to next one.
                                while(<PACKAGES>) {
                                    if (/^$/) {
                                        last;
                                    }
                                }
                                $parsed = {};
                                next;
                            } elsif ((uc($key) eq 'VERSION') && (defined $packages->{$parsed->{'PACKAGE'}}->{'VERSION'})) {
                                # We already have the info on this package and this is the version, add it to the list and then skip to next one
                                my @versions = split(',',$packages->{$parsed->{'PACKAGE'}}->{'VERSION'});
                                if (!(grep {uc($_) eq uc($value)} @versions)) {
                                    push @versions, $value;
                                }
                                $packages->{$parsed->{'PACKAGE'}}->{'VERSION'} = join(',',@versions);
                                while(<PACKAGES>) {
                                    if (/^$/) {
                                        last;
                                    }
                                }
                                $parsed = {};
                                next;
                            } else {
                                $parsed->{uc($key)} = $value;
                            }
                        }
                    }
                    else {
                        s/ //;
                        s/^\.$//;
                        my $body = $_;
                        if(grep {uc($_) eq uc('BODY')} @{$attrs}) {
                            $parsed->{'BODY'} .= $body;
                        }
                    }
                }
                close(PACKAGES);
            }
            if((defined $to) && ($package_indice>$to)) {
                last;
            }
            if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
                # If it's not a local mirror and templates where asked, we still need to extract and store them
                my $distribs = {};
                my @tmp = values(%{$packages});
                $distribs->{"$dist/$section"} = \@tmp;
                cleanup_and_extract($packages_folder,$distribs);
                foreach my $key (keys(%{$packages})) {
                    if(defined $packages->{$key}->{'TEMPLATE'}) {
                        next;
                    }
                    my $filename = $packages_folder."/debconf.d/$dist/$section/".$packages->{$key}->{'PACKAGE'};
                    if(-f $filename) {
                        $packages->{$key}->{'HASTEMPLATE'} = 1;
                        if(grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                            $packages->{$key}->{'TEMPLATE'} = file($filename)->slurp();
                        }
                    }
                }
                rmtree($packages_folder."/debconf.d/");
            }
        }
    }

    foreach my $key (keys(%{$distributions})) {
        my @tmp = values(%{$distributions->{$key}});
        $distributions->{$key} = \@tmp;
    }
    return $distributions;
}


=item store_packages_file
Store and extract the Packages file from the repositories.
=cut
sub store_packages_file {
    my ($packages_folder,$mac,$release) = @_;

    my @repolines = get_repolines($mac);

    my @errors;

    foreach my $repo (@repolines) {
        my $uri = $repo->{'uri'};
        my $dir = $uri;
        $dir =~ s/^http:\/\///;
        my $dist = $repo->{'dist'};
        if(defined($release) && ($dist ne $release)) {
            next;
        }

        my $localmirror = $repo->{'localmirror'};

        foreach my $section (@{$repo->{'sections'}}) {

            foreach my $arch (@{$repo->{'archs'}}) {
              my $packages_file = "$packages_folder/$dir/dists/$dist/$section/binary-$arch/Packages";
              mkpath("$packages_folder/$dir/dists/$dist/$section/binary-$arch/");
              my $res = mirror("$uri/dists/$dist/$section/binary-$arch/Packages.bz2" => $packages_file.".bz2");
              if(is_error($res)) {
                  my $res2 = mirror("$uri/dists/$dist/$section/binary-$arch/Packages.bz2" => $packages_file.".gz");
                  if(is_error($res2)) {
                      push @errors,"Could not download $uri/dists/$dist/$section/binary-$arch/Packages.bz2 : $res";
                      push @errors,"Could not download $uri/dists/$dist/$section/binary-$arch/Packages.gz : $res2";
                  } else {
                      gunzip ($packages_file.".gz" => $packages_file)
                          or push @errors,"could not extract Packages file : $GunzipError";
                  }
              } else {
                  bunzip2 ($packages_file.".bz2" => $packages_file)
                      or push @errors,"could not extract Packages file : $Bunzip2Error";
              }
            }
        }
    }

    return \@errors;
}


=item cleanup_and_extract
Extract templates from packages.

=cut
sub cleanup_and_extract {
    my ($servdir,$distribs) = @_;

    my $tmpdir = "/tmp";
    mkpath($tmpdir);
    while (my ($distsection,$packages) = each(%{$distribs})) {
        my $outdir = "$servdir/debconf.d/$distsection";
        mkpath($outdir);

        foreach my $package (@{$packages}) {
            system( "dpkg -e '$servdir/".$package->{'FILENAME'}."' '$tmpdir/DEBIAN'" );

            if( -f "$tmpdir/DEBIAN/templates" ) {
                my $tmpl = encode_base64(file("$tmpdir/DEBIAN/templates")->slurp());

                open (FILE, ">$outdir/".$package->{'PACKAGE'}) or die "cannot open file";
                print FILE $tmpl;
                close(FILE);
                unlink("$tmpdir/DEBIAN/templates");
            }
        }
    }
    unlink("$tmpdir/DEBIAN");

  return;
}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
