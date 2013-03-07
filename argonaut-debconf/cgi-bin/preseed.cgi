#!/usr/bin/perl

=head1 INTRODUCTION

The script is intended to run as a CGI program. It connects to LDAP and
produces the preseed file based on the Debconf keys for the host.

The usual invocation (this is how the d-i installer requests it unless
  you configure it differently):

  wget http://autoserver/d-i/./natty/preseed.cfg

For the above example to work, you only need to add the following to
the Apache vhost configuration (no need to create directories or
anything):

  ScriptAlias /d-i/natty/preseed.cfg /path/to/cgi-bin/preseed.cgi

Which Debconf keys are included in the generated preseed.cfg?

  - All keys that have the flag "preseed" set.

Which host is preseed.cfg generated for?

  - For the host in LDAP whose ipHostNumber matches the IP from which the
    http request for the preseed file is coming. If you want to retrieve
    the configuration from a different host, pass the ip=ip.add.re.ss 
    parameter. To disable retrieving other hosts' preseed files,
    set "ip 0" in the %parm_valid variable below.

How to test it from the command line, without visiting via CGI and a
  web browser?

  - Run:  QUERY_STRING=ip=HOST_IP perl preseed.cgi

How to conveniently use this script to determine which parameters will
  be included directly on the command line in the PXE config for a host?

  - http://autoserver/d-i/./natty/preseed.cfg?flag=append&ip=HOST_IP


List of GET options supported:

 OPTION:          EXAMPLE:
 debug=0/1        debug=1
 ip=IP            ip=10.0.1.8
 flag=FLAG        flag=preseed

=head1 REFERENCES

https://forge.fusiondirectory.org/projects/debconf/wiki/Preseed

=cut

use warnings;
use strict;

use Net::LDAP;
use Data::Dumper qw/Dumper/;

use lib '/home/wheel/debconf-plugin/lib';
use FusionDirectory::Plugin::Debconf::Init qw/:public/;
use FusionDirectory::Plugin::Debconf::Common qw/:public/;

my %c= %{ $C->preseed_cgi}; # preseed.cgi-specific config

my %parm_valid= qw/ip 1 flag 1 debug 1 must_exist 1/; # Valid GET args
my %query;       # Final query after processing of input parms
my %hash;        # Hash with output data

print "Content-type: text/plain\n\n";

# Do all there is re. the config and input arguments:
my $query= $ENV{QUERY_STRING};
my @query= split /\&/, $query;
$query{ip}= $ENV{REMOTE_ADDR};
@query{qw/flag debug must_exist/}= @c{qw/flag debug must_exist/};
# Transform input @query into %query hash, possibly overriding
# default values
for( @query){
	next unless /^(\w+)=([\w\.]+)$/;
	next unless $parm_valid{$1};
	my( $key, $val)= ( $1, $2);
	$query{$key}= $val;
}
if( $query{debug}) {
	print '# '. scalar localtime, "\n";
	while( my($k,$v)= each %query) { print "# $k=$v\n"}
}

my( $cfg, $n);

if( my $s= FusionDirectory::Plugin::Debconf::System->find2(
 objectClass  => 'GOhard', ipHostNumber => $query{ip})) {

	( $cfg, $n)= $s->Preseed( filter => 'flags='. $query{flag})
		->as_config( debug => $query{debug})
}

unless( $n) {
	print( ( $query{must_exist}? '': '# '). "NO-CONFIG-FOR-$query{ip}")
} else {
	print $cfg
}

exit 0

__END__
=head1 AUTHORS

SPINLOCK - Advanced GNU/Linux networks in commercial and education sectors.

Copyright 2008-2011, Davor Ocelic <docelic@spinlocksolutions.com>

Copyright 2008-2011, SPINLOCK Solutions,
  http://www.spinlocksolutions.com/,
  http://techpubs.spinlocksolutions.com/

=head1 LICENSE

GPL v3 or later. http://www.gnu.org/licenses/gpl.html

=cut
