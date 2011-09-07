package Argonaut::Packages;

use MIME::Base64;
use Path::Class;
use Net::LDAP;
use Config::IniFiles;
use File::Path;

use strict;
use warnings;
use 5.010;

use LWP::Simple;

my $configfile = "/etc/argonaut/argonaut.conf";

my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);

my $arch =   $config->val( repository => "arch"                ,"i386");

=pod
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
    
    my $config = Config::IniFiles->new( -file => $configfile, -allowempty => 1, -nocase => 1);
    my $ldap_url               =   $config->val( ldap => "url"                     ,"localhost");
    my $ldap_port              =   $config->val( ldap => "port"                    ,"389");
    my $ldap_base              =   $config->val( ldap => "base"                    ,"");
    my $ldap_dn                =   $config->val( ldap => "dn"                      ,"");
    my $ldap_password          =   $config->val( ldap => "password"                ,"");
    
	my $ldap = Net::LDAP->new( $ldap_url , port => $ldap_port ) or die "Error while connecting to LDAP : $@";
    
    my $mesg;
    if($ldap_dn ne "") {
        $mesg = $ldap->bind($ldap_dn, password => $ldap_password);
    } else {
        $mesg = $ldap->bind ;    # an anonymous bind
    }
    
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

    my $package_indice = 0;
    my $distributions = {};
    my $deb_filepath = "/tmp/argonaut-packages-tmp";
    mkpath($deb_filepath);
    foreach my $repo ($mesg->entries) {
        my $repoline = $repo->get_value('FAIrepository');
        #~ say "repoline : $repoline";
        my (@items) = split('\|',$repoline);
        my $uri = $items[0];
        my ($dir) = $uri =~ m%.*://[^/]+/(.*)%;
        my $localuri = $uri;
        $localuri =~ s%://[^/]+%://localhost%;
        my $parent_or_opts = $items[1];
        my $dist = $items[2];
        if(defined($release) && ($dist ne $release)) {
            next;
        }
        
        my (@section_list) = split(',',$items[3]);
        
        my $localmirror = ($items[5] == "local");
        
        foreach my $section (@section_list) {
            my $packages_file = "/tmp/Packages";
            my $status = getstore( "$uri/dists/$dist/$section/binary-$arch/Packages" => $packages_file);
            die "Error $status on $uri" unless is_success($status);
            open (PACKAGES, "<$packages_file") or die "cannot open $packages_file";
            my $templatedir = "debconf.d/$dist/$section/";
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
                                my $template = get("$uri/$templatedir/".$parsed->{'PACKAGE'});
                                if(defined $template) {
                                    $parsed->{'TEMPLATE'} = $template;
                                }
                            } elsif (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}) {
                                if(head("$uri/$templatedir/".$parsed->{'PACKAGE'})) {
                                    $parsed->{'HASTEMPLATE'} = 1;
                                }
                            }
                        } else {
                            if ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs})) {
                                getstore("$uri/".$parsed->{'FILENAME'},$deb_filepath."/".$parsed->{'FILENAME'});
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
                    $parsed->{body} .= $_;
                }
            }
            close(PACKAGES);
            if((defined $to) && ($package_indice>$to)) {
                last;
            }
            if(!$localmirror && ((grep {uc($_) eq 'TEMPLATE'} @{$attrs}) || (grep {uc($_) eq 'HASTEMPLATE'} @{$attrs}))) {
                my $distribs = {};
                my @tmp = values(%{$distributions->{"$dist/$section"}});
                $distribs->{"$dist/$section"} = \@tmp;
                cleanup_and_extract($deb_filepath,$distribs);
                foreach my $key (keys(%{$distributions})) {
                    if(defined $distributions->{$key}->{'TEMPLATE'}) {
                        next;
                    }
                    my $filename = $deb_filepath."/$templatedir".$distributions->{$key}->{'PACKAGE'};
                    if(open (my $FILE, "$filename")) {
                        $distributions->{$key}->{'HASTEMPLATE'} = 1;
                        if(grep {uc($_) eq 'TEMPLATE'} @{$attrs}) {
                            $distributions->{$key}->{'TEMPLATE'} = <$FILE>;
                        }
                        close($FILE);
                    }
                }
                rmtree($deb_filepath);
                mkpath($deb_filepath);
            }
        }
    }
    
    foreach my $key (keys(%{$distributions})) {
        my @tmp = values(%{$distributions->{$key}});
        $distributions->{$key} = \@tmp;
    }
    return $distributions;
}


=item cleanup_and_extract
Extract templates from packages.

=cut
sub cleanup_and_extract {
    my ($servdir,$distribs) = @_;

    if (!keys(%{$distribs})) {
        #~ say "No packages on this server";
    }

    while (my ($distsection,$packages) = each(%{$distribs})) {
        #~ $distsection =~ qr{(\w+/\w+)$} or die "$filedir : could not extract dist";
        #~ my $dist = $1;
        my $outdir = "$servdir/debconf.d/$distsection";
        my $tmpdir = "/tmp";
        mkpath($outdir);
        mkpath($tmpdir);
        
        foreach my $package (@{$packages}) {
            system( "dpkg -e '$servdir/".$package->{'FILENAME'}."' '$tmpdir/DEBIAN'" );

            if( -f "$tmpdir/DEBIAN/templates" ) {

                my $tmpl= ""; {
                    local $/=undef;
                    open(my $FILE, "$tmpdir/DEBIAN/templates");
                    $tmpl = &encode_base64(<$FILE>);
                    close($FILE);
                }

                open (FILE, ">$outdir/".$package->{'PACKAGE'}) or die "cannot open file";
                #~ my $line = $package->{'PACKAGE'}.":".$package->{'VERSION'}.":".;
                print FILE $tmpl;
                close(FILE); 
            }
        }
    }

	return;
}

1;
