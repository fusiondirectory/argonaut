#######################################################################
#
# XML::SAX::RPMRepomdHandler -- get and parse RPM Packages.
#
# Copyright (C) 2015 FusionDirectory project
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

package XML::SAX::RPMRepomdHandler;
use base qw(XML::SAX::Base);

  sub new {
    my $class = shift;
    $self = {
      'type' => shift || 'primary',
    };
    return bless $self, $class;
  }

  sub start_document {
    my ($self, $doc) = @_;
    $self->{waiting}  = 0;
    $self->{result}   = undef;
  }

  sub start_element {
    my ($self, $el) = @_;
    if (($self->{waiting} == 0) && ($el->{LocalName} eq 'data') && ($el->{Attributes}->{'{}type'}->{'Value'} eq $self->{type})) {
      $self->{waiting} = 1;
      $self->{key} = undef;
    } elsif (($self->{waiting} == 1) && ($el->{LocalName} eq 'location')) {
      $self->{waiting}++;
      $self->{result} = $el->{Attributes}->{'{}href'}->{'Value'};
    }
  }
1;

=pod
Example:
use LWP::Simple;
use XML::SAX;
use XML::SAX::RPMRepomdHandler;

my $uri = 'http://mirror.centos.org/centos/6/os/x86_64/repodata/';
my $dir = '/tmp/';

my $res = mirror($uri."repomd.xml" => $dir."repomd.xml");
if (is_error($res)) {
  die 'Could not download '.$uri.'repomd.xml: '.$res;
}

my $parser = XML::SAX::ParserFactory->parser(
  Handler => XML::SAX::RPMRepomdHandler->new()
);

$parser->parse_uri($dir."repomd.xml");
print $parser->{Handler}->{result};
=cut
