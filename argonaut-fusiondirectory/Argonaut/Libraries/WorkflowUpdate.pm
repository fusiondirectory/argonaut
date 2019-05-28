#######################################################################
#
# Argonaut::Libraries::WorkflowUpdate -- Tools to maintain worflow through FusionDirectory API
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

package Argonaut::Libraries::WorkflowUpdate;

use strict;
use warnings;

use 5.008;

use Argonaut::Libraries::FusionDirectoryWebService qw(argonaut_get_rest_client argonaut_parse_rest_error);

use JSON;

use Exporter 'import';                                # gives you Exporter's import() method directly
our @EXPORT_OK = qw(&argonaut_supann_update_states);  # symbols to export on request

=item argonaut_supann_update_states
 Updates states in supannRessourceEtatDate if needed
=cut
sub argonaut_supann_update_states {
  my ($verbose) = @_;
  my $client = argonaut_get_rest_client();

  # Hardcoded for now
  # Format: regexp, state, substate, enddate postpone in seconds]
  my @rules = (
    [qr/^{[^}]+}A:.+$/, 'I', 'SupannExpire', 0],
    [qr/^.+$/, 'I', '', 0]
  );

  # Time and date in seconds
  my $now = time();

  $client->GET('/objects/user?filter=(supannRessourceEtatDate=*)&attrs[supannRessourceEtatDate]=*');
  if ($client->responseCode() eq '200') {
    my $users = decode_json($client->responseContent());
    while (my ($dn, $attrs) = each (%$users)) {
      my $supannRessourceEtatDateNewValues = [];
      my $updateNeeded = 0;
      VALUES: foreach my $supannRessourceEtatDate (@{$attrs->{'supannRessourceEtatDate'}}) {
        my ($labelstate, $substate, $start, $end) = split(':', $supannRessourceEtatDate);
        if ($end ne '') {
          my $dt = DateTime->new(
            year  => substr($end, 0, 4),
            month => substr($end, 4, 2),
            day   => substr($end, 6, 2),
          );
          my $endInSeconds = $dt->epoch;
          if ($endInSeconds < $now) {
            # This state has expired
            foreach my $rule (@rules) {
              my ($re, $newState, $newSubstate, $newEnd) = @$rule;
              if ($supannRessourceEtatDate =~ $re) {
                my $newLabelstate = $labelstate;
                if ($newLabelstate =~ s/}[^:]$/}$newState/) {
                  my $newStart = $start;
                  if (($labelstate ne $newLabelstate) || ($substate ne $newSubstate)) {
                    # State or substate changed, update the start date
                    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($now);
                    $newStart = sprintf("%04d%02d%02d", 1900 + $year, 1 + $mon, $mday);
                  }
                  if ($newEnd) {
                    # Postpone end date if appropriate
                    my ($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = gmtime($endInSeconds + $newEnd);
                    $newEnd = sprintf("%04d%02d%02d", 1900 + $year, 1 + $mon, $mday);
                  } else {
                    $newEnd = '';
                  }
                  $updateNeeded = 1;
                  print "Updating $dn from $supannRessourceEtatDate to ".join(':', $newLabelstate, $newSubstate, $newStart, $newEnd)."\n" if $verbose;
                  push(@$supannRessourceEtatDateNewValues, join(':', $newLabelstate, $newSubstate, $newStart, $newEnd));
                  next VALUES;
                } else {
                  print "Could not parse $labelstate into label and state, skipping\n";
                }
                last;
              }
            }
          }
        }
        push(@$supannRessourceEtatDateNewValues, $supannRessourceEtatDate);
      }
      if ($updateNeeded) {
        $client->PUT('/objects/user/'.$dn.'/supannAccountStatus/supannRessourceEtatDate', encode_json($supannRessourceEtatDateNewValues));
        if ($client->responseCode() ne '200') {
          die('Request to REST API failed: '.$client->responseCode().' - '.argonaut_parse_rest_error($client)."\n");
        }
      }
    }
  } else {
    die('Request to REST API failed: '.$client->responseCode().' - '.argonaut_parse_rest_error($client)."\n");
  }
}

1;

__END__
