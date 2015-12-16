#######################################################################
#
# Argonaut::Libraries::Packages -- get and parse Debian Packages.
#
# Copyright (C) 2011-2015 FusionDirectory project
#
# Author: Côme BERNIGAUD
#
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

package Argonaut::Libraries::Packages;

use strict;
use warnings;

use 5.008;

use MIME::Base64;
use Path::Class;
use Net::LDAP;
use File::Path;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);
use IO::Uncompress::Gunzip qw(gunzip $GunzipError);
use LWP::Simple;
use Encode qw(encode);
use XML::SAX::RPMHandler;
use XML::SAX::RPMRepomdHandler;
use XML::SAX;

use Argonaut::Libraries::Common qw(:ldap :config);

BEGIN
{
  use Exporter ();
  use vars qw(@EXPORT_OK @ISA $VERSION);
  $VERSION = '2011-04-11';
  @ISA = qw(Exporter);

  @EXPORT_OK = qw(get_repolines get_packages_info store_packages_file cleanup_and_extract);
}

=pod
=item get_repolines
Get repolines from ldap

=cut
sub get_repolines {
    my ($mac,$cn) = @_;

    my $config = argonaut_read_config;

    my ($ldap,$ldap_base) = argonaut_ldap_handle($config);

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
        my ($uri,$parent,$release,$sections,$install,$local,$archs,$dist,$pathmask) = split('\|',$repoline);
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
          'release'     => $release,
          'sections'    => $sections_array,
          'installrepo' => $install,
          'localmirror' => ($local eq "local"),
          'archs'       => [split(',',$archs)],
          'dist'        => $dist,
          'pathmask'    => $pathmask
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
    if(defined($release) && ($repo->{'release'} ne $release)) {
      next;
    }
    if ($repo->{'dist'} eq 'debian') {
      parse_package_list_debian($packages_folder,\$package_indice,$distributions,$repo,$attrs,$filters,$from,$to);
    } elsif ($repo->{'dist'} eq 'centos') {
      parse_package_list_centos($packages_folder,\$package_indice,$distributions,$repo,$attrs,$filters,$from,$to);
    }
  }

  foreach my $key (keys(%{$distributions})) {
    my @tmp = values(%{$distributions->{$key}});
    $distributions->{$key} = \@tmp;
  }
  return $distributions;
}

sub parse_package_list_centos {
  my ($packages_folder,$package_indice,$distributions,$repo,$attrs,$filters,$from,$to) = @_;

  my $uri = $repo->{'uri'};
  my $localuri = $uri;
  $localuri =~ s/^http:\/\///;

  my $handler = XML::SAX::RPMHandler->new(
    undef,
    {
      'name' => 'PACKAGE',
      'description' => sub {
        my ($package, undef, $data, $attrs) = @_;
        $package->{'DESCRIPTION'} = encode_base64(encode('utf8',$data));
      },
      'version' => sub {
        my ($package, undef, $data, $attrs) = @_;
        $package->{'VERSION'} = $attrs->{'{}ver'}->{'Value'}.'-'.$attrs->{'{}rel'}->{'Value'};
      }
    },
    $filters,
    $from,
    $to,
    $$package_indice
  );
  my $parser = XML::SAX::ParserFactory->parser(
    Handler => $handler
  );

  foreach my $section (@{$repo->{'sections'}}) {
    if(!defined $distributions->{$repo->{'release'}."/$section"}) {
      $distributions->{$repo->{'release'}."/$section"} = {};
    }
    $handler->{packages} = $distributions->{$repo->{'release'}."/$section"};
    foreach my $arch (@{$repo->{'archs'}}) {
      my $relpath = $repo->{'pathmask'};
      $relpath =~ s/%RELEASE%/$repo->{'release'}/i;
      $relpath =~ s/%SECTION%/$section/i;
      $relpath =~ s/%ARCH%/$arch/i;
      my $primary_file = "$packages_folder/$localuri/".$relpath."/primary.xml";
      eval {
        $parser->parse_uri($primary_file);
      };
      if ($@ && ($@ !~ m/^LIMIT_REACHED/)) {
        die $@;
      }
    }
  }
  $$package_indice = $handler->{indice};
}

sub parse_package_list_debian {
  my ($packages_folder,$package_indice,$distributions,$repo,$attrs,$filters,$from,$to) = @_;

  my $uri = $repo->{'uri'};
  my $localuri = $uri;
  $localuri =~ s/^http:\/\///;

  my $localmirror = $repo->{'localmirror'};
  if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
      push @{$attrs},'FILENAME' if (not (grep {uc($_) eq 'FILENAME'} @{$attrs}));
  }

  foreach my $section (@{$repo->{'sections'}}) {
      if(!defined $distributions->{$repo->{'release'}."/$section"}) {
          $distributions->{$repo->{'release'}."/$section"} = {};
      }
      my $packages = $distributions->{$repo->{'release'}."/$section"};
      foreach my $arch (@{$repo->{'archs'}}) {
          my $packages_file = "$packages_folder/$localuri/dists/".$repo->{'release'}."/$section/binary-$arch/Packages";
          open (PACKAGES, "<$packages_file") or next;
          my $parsed = {};
          while (<PACKAGES>) {
              if (/^$/) {
                  # Empty line means this package info lines are over
                  $$package_indice++;
                  if((! defined $from) || ($$package_indice>$from)) {
                      if($localmirror) {
                          # If it's a local mirror, it's supposed to run the debconf crawler and have the template extracted
                          # So we just download it (if it's not there, we assume there is no template for this package)
                          if (grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                              my $template = get("$uri/debconf.d/".$repo->{'release'}."/$section/".$parsed->{'PACKAGE'});
                              if(defined $template) {
                                  $parsed->{'HASTEMPLATE'} = 1;
                                  $parsed->{'TEMPLATE'} = $template;
                              }
                          } elsif (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}) {
                              if(head("$uri/debconf.d/".$repo->{'release'}."/$section/".$parsed->{'PACKAGE'})) {
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
                  if((! defined $to) || ($$package_indice<$to)) {
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
      if((defined $to) && ($$package_indice>$to)) {
          last;
      }
      if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
          # If it's not a local mirror and templates where asked, we still need to extract and store them
          my $distribs = {};
          my @tmp = values(%{$packages});
          $distribs->{$repo->{'release'}."/$section"} = \@tmp;
          cleanup_and_extract($packages_folder,$distribs);
          foreach my $key (keys(%{$packages})) {
              if(defined $packages->{$key}->{'TEMPLATE'}) {
                  next;
              }
              my $filename = $packages_folder."/debconf.d/".$repo->{'release'}."/$section/".$packages->{$key}->{'PACKAGE'};
              if(-f $filename) {
                  $packages->{$key}->{'HASTEMPLATE'} = 1;
                  if(grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                      $packages->{$key}->{'TEMPLATE'} = file($filename)->slurp();
                  }
              }
          }
      }
  }
}

=item store_packages_file
Store and extract the Packages file from the repositories.
=cut
sub store_packages_file {
  my ($packages_folder,$mac,$release) = @_;

  my @repolines = get_repolines($mac);

  my @errors;

  foreach my $repo (@repolines) {
    if(defined($release) && ($repo->{'release'} ne $release)) {
      next;
    }
    my $repo_errors;
    if ($repo->{'dist'} eq 'debian') {
      $repo_errors = store_package_list_debian($packages_folder,$repo);
    } elsif ($repo->{'dist'} eq 'centos') {
      $repo_errors = store_package_list_centos($packages_folder,$repo);
    }
    @errors = (@errors, @$repo_errors);
  }

  return \@errors;
}

sub store_package_list_centos {
  my ($packages_folder,$repo) = @_;

  my $uri = $repo->{'uri'};
  my $dir = $uri;
  my @errors;
  $dir =~ s/^http:\/\///;
  $dir = "$packages_folder/$dir";

  my $parser = XML::SAX::ParserFactory->parser(
    Handler => XML::SAX::RPMRepomdHandler->new()
  );

  foreach my $section (@{$repo->{'sections'}}) {
    foreach my $arch (@{$repo->{'archs'}}) {
      my $relpath = $repo->{'pathmask'};
      $relpath =~ s/%RELEASE%/$repo->{'release'}/i;
      $relpath =~ s/%ARCH%/$arch/i;
      $relpath =~ s/%SECTION%/$section/i;
      mkpath($dir.$relpath."/repodata");
      my $res = mirror($uri.$relpath."repodata/repomd.xml" => $dir.$relpath."repodata/repomd.xml");
      if(is_error($res)) {
        push @errors,"Could not download $uri".$relpath."repodata/repomd.xml: $res";
        next;
      }
      $parser->parse_uri($dir.$relpath."repodata/repomd.xml");
      my $primary = $parser->{Handler}->{result};
      $res = mirror($uri."/$relpath/".$primary => $dir."/$relpath/".$primary);
      if(is_error($res)) {
        push @errors,"Could not download $uri"."/$relpath/".$primary.": $res";
        next;
      }
      gunzip ($dir."/$relpath/".$primary => $dir."/$relpath/primary.xml")
        or push @errors,"could not extract Packages file : $GunzipError";
    }
  }

  return \@errors;
}

sub store_package_list_debian {
  my ($packages_folder,$repo) = @_;

  my $uri = $repo->{'uri'};
  my $dir = $uri;
  my @errors;
  $dir =~ s/^http:\/\///;
  $dir = "$packages_folder/$dir";

  foreach my $section (@{$repo->{'sections'}}) {
      my $relpath = "dists/".$repo->{'release'}."/$section";
      foreach my $arch (@{$repo->{'archs'}}) {
        my $packages_file = "/$relpath/binary-$arch/Packages";
        mkpath("$dir/$relpath/binary-$arch/");
        my $res = mirror($uri.$packages_file.".bz2" => $dir.$packages_file.".bz2");
        if(is_error($res)) {
            my $res2 = mirror($uri.$packages_file.".gz" => $dir.$packages_file.".gz");
            if(is_error($res2)) {
                push @errors,"Could not download $uri".$packages_file.".bz2 : $res";
                push @errors,"Could not download $uri".$packages_file.".gz : $res2";
            } else {
                gunzip ($dir.$packages_file.".gz" => $dir.$packages_file)
                    or push @errors,"could not extract Packages file : $GunzipError";
            }
        } else {
            bunzip2 ($dir.$packages_file.".bz2" => $dir.$packages_file)
                or push @errors,"could not extract Packages file : $Bunzip2Error";
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
            if ((-f "$outdir/".$package->{'PACKAGE'}) || (-f "$outdir/".$package->{'PACKAGE'}.'-NOTEMPLATE')) {
              next;
            }
            system( "dpkg -e '$servdir/".$package->{'FILENAME'}."' '$tmpdir/DEBIAN'" );

            if( -f "$tmpdir/DEBIAN/templates" ) {
                my $tmpl = encode_base64(file("$tmpdir/DEBIAN/templates")->slurp());

                open (FILE, ">$outdir/".$package->{'PACKAGE'}) or die "cannot open file";
                print FILE $tmpl;
                close(FILE);
                unlink("$tmpdir/DEBIAN/templates");
            } else {
                open (FILE, ">$outdir/".$package->{'PACKAGE'}.'-NOTEMPLATE') or die "cannot open file";
                print FILE "1\n";
                close(FILE);
            }
        }
    }
    unlink("$tmpdir/DEBIAN");

  return;
}

1;

__END__

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
