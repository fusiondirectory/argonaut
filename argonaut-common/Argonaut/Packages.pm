#######################################################################
#
# Argonaut::Packages package -- get and parse Debian Packages.
#
# Copyright (c) 2008 by Cajus Pollmeier <pollmeier@gonicus.de>
# Copyright (C) 2011 FusionDirectory project
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


package Argonaut::Packages;

use MIME::Base64;
use Argonaut::Common;
use Path::Class;
use Net::LDAP;
use Config::IniFiles;
use File::Path;
use IO::Uncompress::Bunzip2 qw(bunzip2 $Bunzip2Error);

use strict;
use warnings;
use 5.010;

use LWP::Simple;

my $configfile = "/etc/argonaut/argonaut.conf";
my $ldap_configfile = "/etc/ldap/ldap.conf";

my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

my $arch =   $config->val( repository => "arch"                ,"i386");
my $packages_folder =   $config->val( repository => "packages_folder"                ,"/tmp/Packages");

=pod
=item get_repolines
Get repolines from ldap

=cut
sub get_repolines {
    my ($mac) = @_;
    
    my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);
    #~ my $ldap_url               =   $config->val( ldap => "url"                     ,"localhost");
    #~ my $ldap_port              =   $config->val( ldap => "port"                    ,"389");
    #~ my $ldap_base              =   $config->val( ldap => "base"                    ,"");
    my $ldap_dn                =   $config->val( ldap => "dn"                      ,"");
    my $ldap_password          =   $config->val( ldap => "password"                ,"");
    
  #~ my $ldap = Net::LDAP->new( $ldap_url , port => $ldap_port ) or die "Error while connecting to LDAP : $@";
    my $ldapinfos = Argonaut::Common::goto_ldap_init ($ldap_configfile, 0, $ldap_dn, 0, $ldap_password);
    my $ldap = $ldapinfos->{'HANDLE'};
    my $ldap_base = $ldapinfos->{'BASE'};
    
    my $mesg;
    #~ if($ldap_dn ne "") {
        #~ $mesg = $ldap->bind($ldap_dn, password => $ldap_password);
    #~ } else {
        #~ $mesg = $ldap->bind ;    # an anonymous bind
    #~ }
    
    if(defined $mac) {
        $mesg = $ldap->search(
            base => $ldap_base,
            filter => "(&(objectClass=FAIrepositoryServer)(macAddress=$mac))",
            attrs => [ 'FAIrepository', 'cn' ] );
    } else {
        $mesg = $ldap->search(
            base => $ldap_base,
            filter => "objectClass=FAIrepositoryServer",
            attrs => [ 'FAIrepository', 'cn' ] );
    }
    
    $mesg->code && die "Error while searching repositories :".$mesg->error;
 
    $ldap->unbind();
 
    return $mesg->entries;
}


=item get_packages_info
Get packages list with all requested attrs.
Uses the Packages file from the server for that.
If no mac is provided, all servers (for the specified release) in the ldap are checked.

=cut
sub get_packages_info {
    my ($mac,$release,$attrs,$filters,$from,$to) = @_;
    
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
    
    my @repos = get_repolines($mac);

    my $package_indice = 0;
    my $distributions = {};
    my $deb_filepath = "/tmp/argonaut-packages-tmp";
    mkpath($deb_filepath);
    foreach my $repo (@repos) {
        my $repoline = $repo->get_value('FAIrepository');
        
        my (@items) = split('\|',$repoline);
        my ($uri,$parent_or_opts,$dist) = @items;
        my ($dir) = $uri =~ m%.*://[^/]+/(.*)%;
        my $localuri = $uri;
        $localuri =~ s%://[^/]+%://localhost%;
        if(defined($release) && ($dist ne $release)) {
            next;
        }
        
        my (@section_list) = split(',',$items[3]);
        
        my $localmirror = ($items[5] eq "local");
        if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
            push @{$attrs},'FILENAME' if (not (grep {uc($_) eq 'FILENAME'} @{$attrs}));
        }
        
        foreach my $section (@section_list) {
            my $localuri = $uri;
            $localuri =~ s/^http:\/\///;
            my $packages_file = "$packages_folder/$localuri/dists/$dist/$section/binary-$arch/Packages";
            open (PACKAGES, "<$packages_file") or next;
            if(!defined $distributions->{"$dist/$section"}) {
                $distributions->{"$dist/$section"} = {};
            }
            my $packages = $distributions->{"$dist/$section"};
            my $parsed = {};
            while (<PACKAGES>) {
                if (/^$/) {
                    $package_indice++;
                    if((! defined $from) || ($package_indice>$from)) {
                        if($localmirror) {
                            if (grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                                my $template = get("$uri/debconf.d/$dist/$section/".$parsed->{'PACKAGE'});
                                if(defined $template) {
                                    $parsed->{'TEMPLATE'} = $template;
                                }
                            } elsif (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}) {
                                if(head("$uri/debconf.d/$dist/$section/".$parsed->{'PACKAGE'})) {
                                    $parsed->{'HASTEMPLATE'} = 1;
                                }
                            }
                        } else {
                            if ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs})) {
                                my $filedir = $parsed->{'FILENAME'};
                                $filedir =~ s/[^\/]+$//;
                                mkpath($deb_filepath."/".$filedir);
                                mirror("$uri/".$parsed->{'FILENAME'},$deb_filepath."/".$parsed->{'FILENAME'});
                            }
                        }
                        if(defined $packages->{$parsed->{'PACKAGE'}}) {
                            if(grep {uc($_) eq 'VERSION'} @{$attrs}) {
                                if(defined $packages->{$parsed->{'PACKAGE'}}->{'VERSION'}) {
                                    $packages->{$parsed->{'PACKAGE'}}->{'VERSION'} .= ",".$parsed->{'VERSION'};
                                } else {
                                    $packages->{$parsed->{'PACKAGE'}} = $parsed;
                                }
                            }
                        } else {
                            $packages->{$parsed->{'PACKAGE'}} = $parsed;
                        }
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
                            next;
                        }
                    }
                    if (grep {uc($_) eq uc($key)} @{$attrs}) {
                        if(uc($key) eq 'DESCRIPTION') {
                            $parsed->{'DESCRIPTION'} = encode_base64($value);
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
            if((defined $to) && ($package_indice>$to)) {
                last;
            }
            if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
                my $distribs = {};
                my @tmp = values(%{$packages});
                $distribs->{"$dist/$section"} = \@tmp;
                cleanup_and_extract($deb_filepath,$distribs);
                foreach my $key (keys(%{$packages})) {
                    if(defined $packages->{$key}->{'TEMPLATE'}) {
                        next;
                    }
                    my $filename = $deb_filepath."/debconf.d/$dist/$section/".$packages->{$key}->{'PACKAGE'};
                    if(-f $filename) {
                        $packages->{$key}->{'HASTEMPLATE'} = 1;
                        if(grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                            $packages->{$key}->{'TEMPLATE'} = file($filename)->slurp();
                        }
                    }
                }
                rmtree($deb_filepath."/debconf.d/");
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
    my ($mac,$release) = @_;
    
    my @repos = get_repolines($mac);

    my @errors;

    foreach my $repo (@repos) {
        my $repoline = $repo->get_value('FAIrepository');
        
        my (@items) = split('\|',$repoline);
        my $uri = $items[0];
        my $dist = $items[2];
        if(defined($release) && ($dist ne $release)) {
            next;
        }
        
        my (@section_list) = split(',',$items[3]);
        
        my $localmirror = ($items[5] eq "local");
        
        foreach my $section (@section_list) {
            
            my $dir = $uri;
            $dir =~ s/^http:\/\///;
            my $packages_file = "$packages_folder/$dir/dists/$dist/$section/binary-$arch/Packages";
            mkpath("$packages_folder/$dir/dists/$dist/$section/binary-$arch/");
            my $res = mirror("$uri/dists/$dist/$section/binary-$arch/Packages.bz2" => $packages_file.".bz2");
            if(is_error($res)) {
                push @errors,"Could not download $uri/dists/$dist/$section/binary-$arch/Packages.bz2 : $res";
            } else {
                bunzip2 ($packages_file.".bz2" => $packages_file)
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

    #~ if (!keys(%{$distribs})) {
        #~ say "No packages on this server";
    #~ }

    while (my ($distsection,$packages) = each(%{$distribs})) {
        my $outdir = "$servdir/debconf.d/$distsection";
        my $tmpdir = "/tmp";
        mkpath($outdir);
        mkpath($tmpdir);
        
        foreach my $package (@{$packages}) {
            system( "dpkg -e '$servdir/".$package->{'FILENAME'}."' '$tmpdir/DEBIAN'" );

            if( -f "$tmpdir/DEBIAN/templates" ) {
                my $tmpl = encode_base64(file("$tmpdir/DEBIAN/templates")->slurp());
                
                open (FILE, ">$outdir/".$package->{'PACKAGE'}) or die "cannot open file";
                print FILE $tmpl;
                close(FILE); 
            }
            unlink("$tmpdir/DEBIAN/templates");
        }
    }

  return;
}

1;
