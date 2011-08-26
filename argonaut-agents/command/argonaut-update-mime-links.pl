#!/usr/bin/perl
#
# (C) 2008 Carsten Sommer <carsten.sommer@gonicus.de>
#
# Generate mimelinks for KDE, GNOME and mime.types aware applications.
# The script only works on the users side - i.e. applinks have to exist
# before beeing modified, no new entries are created/copied from system
# directories.

use strict;
use warnings;
use lib "/usr/lib/argonaut";

use Net::LDAP;
use Net::LDAP::LDIF;
use Net::LDAP::Util qw(:escape);
use Argonaut::Common qw(:ldap :file :array);
use Argonaut::LDAP qw(ldap_get_object);

use Tie::File;
use File::Find ();


# init ldap connection

my $HOME = $ENV{'HOME'};
my $ldapinfo = goto_ldap_parse_config_ex(); #ref to hash
my ($ldapbase,$ldapuris) = ($ldapinfo->{"LDAP_BASE"}, $ldapinfo->{"LDAP_URIS"});
my $ldap = Net::LDAP->new( $ldapuris ) or die "$@";
my $mesg = $ldap->bind ;    # an anonymous bind


# get mime type settings from LDAP server 

$mesg = $ldap->search(  base   => "$ldapbase",
                        filter => "(&(objectclass=gotoMimeType))" );
$mesg->code && die $mesg->error;
my @entries = $mesg->entries;



# remove profilerc and mailcap

system("rm -f $HOME/.kde/share/config/profilerc");
system("rm -f $HOME/.mailcap");



# clear MimeType lines from .local/share/applications

use vars qw/*name/;
*name   = *File::Find::name;
my @files;

sub wanted {
    /^.*\.desktop\z/s
    && push (@files, "$name");
}

File::Find::find({wanted => \&wanted}, "$HOME/.local/share/applications");
File::Find::find({wanted => \&wanted}, "$HOME/.kde/share/applnk");


foreach my $filename (@files) {
	tie my @filelines, 'Tie::File', $filename or die;
	@filelines = grep { !/^MimeType=.*/ } @filelines;
	untie @filelines or die "$!";
}


# generate new files

foreach my $entry (@entries) {

	# get configured applications for a mimetype

	my $group = $entry->get_value('gotoMimeGroup');
	my $type = $entry->get_value('cn');
	my $mimetype = $group . "/" . $type;


	# configure mime type file patterns
	
	my $patterns = $entry->get_value('gotoMimeFilePattern', asref => 1 );
	my $patternstring = "";

	foreach my $pattern (@$patterns) {
		if ( ! $patternstring eq "" ) {
			$patternstring .= ";";
		}
		$patternstring .= $pattern;
	}

	system("mkdir -p $HOME/.kde/share/mimelnk/$group");
	open(FILE, "> $HOME/.kde/share/mimelnk/$group/$type.desktop");
	print(FILE "[Desktop Entry]\n");
	print(FILE "Comment=Default Comment\n");
	print(FILE "Hidden=false\n");
	print(FILE "Patterns=$patternstring\n");
	print(FILE "X-KDE-AutoEmbed=false\n");
	close(FILE);

	

	# loop through all configured applications

	my $apps = $entry->get_value('gotoMimeApplication', asref => 1 );

	foreach my $app (@$apps) {
		my $prio = $app;
		$app =~ s/(.*)\|.*/$1/;
		$prio =~ s/.*\|(.*)/$1/;
		$prio = $prio + 1;
		print "configuring mimetype for application $app \n";

		# add mimetype lines to .local/share/applications/*

		my $found;
		my @lines;
		foreach my $file (@files) {

			$found = 0;

		    	open (FILE, $file);
			@lines = <FILE>;
			if ( grep(/^Exec.*$app/, @lines)) {
				$found = 1;
				#print "found $app : $file\n";
			}
			close(FILE);

	    		if ($found == 1) { 
				#print "modifying $file\n";
		    		open (FILE, "> $file");

				if ( grep (/^MimeType=/, @lines)) {
					foreach my $line (@lines) {
						$line =~ s/(MimeType=.*)/$1;$mimetype/;
						print(FILE $line);
					}
				} else {
					foreach my $line (@lines) {
						print(FILE $line);
					}
					print(FILE "MimeType=$mimetype\n"); 

				}
				close(FILE);
			}

		}

		# add mimetype to profilerc
		
		my $iprio = @$apps - $prio + 1;
		open(FILE, ">> $HOME/.kde/share/config/profilerc");
		print(FILE  "[$mimetype - $prio]\n");
		print(FILE "AllowAsDefault=true\n");
		print(FILE "Application=kde-$app.desktop\n");
		print(FILE "GenericServiceType=Application\n");
		print(FILE "Preference=$iprio\n");
		print(FILE "ServiceType=$mimetype\n\n");
		close(FILE);

		# add prio 1 mimetype to mailcap

		if ($prio == 1) {
			open(FILE, ">> $HOME/.mailcap");
			print(FILE "$mimetype;$app '%s'\n");
			close(FILE);
		}
	}
}

# rebuild KDE sycoca
system("kbuildsycoca --noincremental");


