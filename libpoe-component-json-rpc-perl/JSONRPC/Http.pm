##############################
#  This code is part of FusionDirectory (http://www.fusiondirectory.org/)
#  Copyright (C) 2011  FusionDirectory
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
#  Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA  02111-1307  USA
##############################

package POE::Component::Server::JSONRPC::Http;
use strict;
use warnings;
use POE::Component::Server::JSONRPC; # for old Perl 5.005
use base qw(POE::Component::Server::JSONRPC);

our $VERSION = '0.01';

use POE qw/
    Component::Server::SimpleHTTP
    Filter::Line
    /;
use JSON::Any;

use Data::Dumper;

sub new {
    my $class = shift;
    return $class->SUPER::new(@_);
}

sub poe_init_server {
    my ($self, $kernel, $session, $heap) = @_[OBJECT, KERNEL, SESSION, HEAP];
    
    $kernel->alias_set( 'JSONRPCHTTP' );
    
    $self->{http} = POE::Component::Server::SimpleHTTP->new(
        'ALIAS'         =>      'HTTPD',
        'PORT'          =>      $self->{Port},
        $self->{Address}     ? ('ADDRESS'     => $self->{Address} )     : (),
        $self->{Hostname}    ? ('HOSTNAME'    => $self->{Hostname} )    : (),
        'HANDLERS'      =>      [
                {
                        'DIR'           =>      '.*',
                        'SESSION'       =>      'JSONRPCHTTP',
                        'EVENT'         =>      'input_handler',
                },
        ],

        'LOGHANDLER' => {},
    );
}

sub poe_send {
    my ($kernel,$response, $content) = @_[KERNEL,ARG0..$#_];
    
    #HTTP
    $response->code( 200 );
    $response->content( $content );
    
    $kernel->post( 'HTTPD', 'DONE', $response );
}

1;
