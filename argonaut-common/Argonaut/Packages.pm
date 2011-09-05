package Argonaut::Packages;

use MIME::Base64;
use Path::Class;
use Net::LDAP;
use Config::IniFiles;

use strict;
use warnings;
use 5.010;

use LWP::Simple;

my $configfile = "/etc/argonaut/argonaut.conf";

my $arch = "i386";

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
    foreach my $repo ($mesg->entries) {
        my $repoline = $repo->get_value('FAIrepository');
        say "repoline : $repoline";
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
        
        foreach my $section (@section_list) {
            my $packages_file = "/tmp/Packages";
            #~ say $packages_file;
            #~ say $uri;
            #~ say $dir;
            #~ say $localuri;
            my $status = getstore( "$uri/dists/$dist/$section/binary-$arch/Packages" => $packages_file);
            die "Error $status on $uri" unless is_success($status);
            open (PACKAGES, "<$packages_file") or die "cannot open $packages_file";
            my $templatedir = "debconf.d/$dist/$section/";
            my $packages = [];
            my $parsed = {};
            while (<PACKAGES>) {
                if (/^$/) {
                    $package_indice++;
                    if((! defined $from) || ($package_indice>$from)) {
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
                        push @{$packages},$parsed;
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
            $distributions->{"$dist/$section"} = $packages;
            if((defined $to) && ($package_indice>$to)) {
                last;
            }
        }
    }
    
    return $distributions;
}

1;
