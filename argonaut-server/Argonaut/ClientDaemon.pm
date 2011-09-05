##########################################################################
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
#  Foundation, Inc., 51 Franklin St, Fifth Floor, Boston, MA 02110-1301, USA.
#############################################################################

package
    Argonaut::ClientDaemon;

use base qw(JSON::RPC::Procedure); # requires Perl 5.6 or later
use Data::Dumper;

use strict;
use warnings;
use 5.010;

sub trigger_action_halt : Public {
	my ($s, $args) = @_;
    print "shutdown ".Dumper($args)."\n";
    return "shuting down";
}

sub trigger_action_reboot : Public {
	my ($s, $args) = @_;
    say "reboot";
    return "rebooting";
}

sub echo : Public {
	my ($s, $args) = @_;
    print "echo ".Dumper($args)."\n";
    return $args;
}

package
    Argonaut::ClientDaemon::system;

sub describe {
    say "system.describe";
    return {
        sdversion => "1.0",
        name      => 'Argonaut::ClientDaemon',
    };
}

1;
