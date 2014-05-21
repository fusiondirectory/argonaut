#######################################################################
#
# Argonaut::Fuse::Preseed
#
# Copyright (c) 2005,2006,2007 by Jan-Marek Glogowski <glogow@fbihome.de>
# Copyright (c) 2008 by Cajus Pollmeier <pollmeier@gonicus.de>
# Copyright (c) 2008,2009,2010 by Jan Wenzel <wenzel@gonicus.de>
# Copyright (C) 2011,2013 FusionDirectory project <contact@fusiondirectory.org>
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

package Argonaut::Fuse::Modules::Preseed;

use strict;
use warnings;

use 5.008;

use Argonaut::Common qw(:ldap :file);
use Argonaut::Debconf::Init qw(:public);
use Argonaut::Debconf::Common qw(:public);

my $log = Log::Handler->get_logger("argonaut-fuse");

sub get_module_info {
  return "Automatic Debconf Installation";
};

sub get_module_settings {
  return argonaut_get_generic_settings(
    'argonautFusePreseedConfig',
    {
      'admin'     => "argonautFuseOpsiAdmin",
      'password'  => "argonautFuseOpsiPassword",
      'server'    => "argonautFuseOpsiServer",
      'lang'      => "argonautFuseOpsiLang"
    },
    $main::ldap_configfile,$main::ldap_dn,$main::ldap_password,$main::client_ip
  );
}

sub get_pxe_config {
  my ($filename) = shift || return undef;
  my $settings = get_module_settings();
}

sub get_pxe_config {
  my $filename = shift || return undef;
  my %found;

  my @search = ( 'objectClass', 'debconfStartup');
  my ($mac, $s, $i);

  $mac = argonaut_get_mac_pxe($filename);
  push @search, 'macAddress', $mac;

  my @sys = (Argonaut::Debconf::System->find2(@search));
  $i = Net::LDAP::Class::SimpleIterator->new(code => sub {shift @sys});

  my @filenames;
  if ($s = $i->next) {
    $mac = $s->macAddress or next;
    $mac =~ s/:/-/g;

    # XXX Retrieving whole config here is expensive, see if we
    # can just pick out the names, retrieve the config later
    # if it is actually requested.
    my $content = $s->PXE;
    if (not $content) {
      # empty content, we can't create the PXE file
      $log->info("No Preseed configuration for client with MAC ${mac}\n");
      return undef;
    }

    my $kernel = "kernel ${\( $$content{system}->gotoBootKernel)}";
    my $append = $content{system}->gotoKernelParameters;
    $append =~ s/%append/ $content->as_append_line /e;
    my $hostname = $s->cn;

    $i->finish;

    my $code = &main::write_pxe_config_file($hostname, $filename, $kernel, $append);
    if ($code == 0) {
      $log->info("$filename - successfully returned preseed PXE info\n");
      return time;
    } else {
      $log->info("$filename - error: $code\n");
      return undef;
    }
  } else {
    $log->info("No Preseed configuration for client with MAC ${mac}\n");
    return undef;
  }
}

1;

__END__

