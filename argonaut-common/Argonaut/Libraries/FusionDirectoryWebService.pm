#######################################################################
#
# Argonaut::Libraries::FusionDirectoryWebService -- Contact FusionDirectory REST API
#
# Copyright (C) 2018-2019 FusionDirectory project
#
# Author: Côme Chilliet
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

package Argonaut::Libraries::FusionDirectoryWebService;

use strict;
use warnings;

use 5.008;

use REST::Client;
use JSON;

use Argonaut::Libraries::Common qw(:config);

use Exporter 'import';                          # gives you Exporter's import() method directly
our @EXPORT_OK = qw(&argonaut_get_rest_client); # symbols to export on request

=item argonaut_get_rest_client
 Get REST client connection using information from configuration file
=cut
sub argonaut_get_rest_client {
  my $config = argonaut_read_config;

  my $client = REST::Client->new();
  $client->setHost($config->{'rest_endpoint'});
  my %postBody = (
    'user'      => $config->{'rest_login'},
    'password'  => $config->{'rest_password'}
  );
  if ($config->{'rest_ldap'} ne '') {
    $postBody{'ldap'} = $config->{'rest_ldap'};
  }
  $client->POST(
    '/login',
    encode_json(\%postBody)
  );
  if ($client->responseCode() eq '200') {
    my $token = JSON->new->utf8->allow_nonref->decode($client->responseContent());
    $client->addHeader('Session-Token', $token);
  } else {
    die('Connection to REST API failed: '.$client->responseCode().' '.$client->responseContent());
  }

  return $client;
}

1;

__END__
