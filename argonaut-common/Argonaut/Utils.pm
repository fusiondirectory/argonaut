#######################################################################
#
# Argonaut::Utils package -- Calculate the progress bar for fai install.
#
# Copyright (c) 2008 by Cajus Pollmeier <pollmeier@gonicus.de>
# Copyright (C) 2011-2013 FusionDirectory project
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

package Argonaut::Utils;

use strict;
use warnings;

use 5.008;

use POSIX;
use Locale::gettext;
use MIME::Base64;

use Exporter;

@ISA = qw(Exporter);
@EXPORT = qw(process_input);

BEGIN {}

END {}

### Start ######################################################################

# I18N setup
setlocale(LC_MESSAGES, "");
textdomain("fai-progress");

use constant TG_NONE    => 0;
use constant TG_INSTALL => 1;
use constant TG_CONFIG  => 1;
use constant TG_WAITACTIVE  => 2;
use constant TG_HWDETECT  => 3;

# "Global" variables
my $percent= 0;
my $pkg_step= 0.0;
my $scr_step= 0.0;
my $task= TG_NONE;
my $action= gettext("Initializing FAI");

sub process_input($)
{
  my %result;
  my $line= shift;
  chomp($line);

  # Assume no errors
  $result{'status'}= 0;

  # Do regex
  if ( $line =~ m/^fai-progress: hangup$/ ) {
    $result{'status'}= -1;
  } elsif ( $line =~ /^Calling task_confdir$/ ) {
    %result = ( 'status' => 0, 'percent' => 0, 'task' => "task_confdir",
                'action' => gettext("Retrieving initial client configuration"));
  } elsif ( $line =~ /^Calling task_setup$/ ) {
    %result = ( 'status' => 0, 'percent' => 1, 'task' => "task_setup",
                'action' => gettext("Gathering client information"));
  } elsif ( $line =~ /^Calling task_defclass$/ ) {
    %result = ( 'status' => 0, 'percent' => 1, 'task' => "task_defclass",
                'action' => gettext("Defining installation classes"));
  } elsif ( $line =~ /^Calling task_defvar$/ ) {
    %result = ( 'status' => 0, 'percent' => 1, 'task' => "task_defvar",
                'action' => gettext("Defining installation variables"));
  } elsif ( $line =~ /^FAI_ACTION: install$/ ) {
    %result = ( 'status' => 0, 'percent' => 2, 'task' => "task_defvar",
                'action' => gettext("Starting installation"));
  } elsif ( $line =~ /^Calling task_install$/ ) {
    %result = ( 'status' => 0, 'percent' => 2, 'task' => "task_defvar",
                'action' => gettext("Starting installation"));
  } elsif ( $line =~ /^Calling task_partition$/ ) {
    %result = ( 'status' => 0, 'percent' => 2, 'task' => "task_partition",
                'action' => gettext("Inspecting harddisks"));
  } elsif ( $line =~ /^Creating partition table/ ) {
    %result = ( 'status' => 0, 'percent' => 2, 'task' => "task_partition",
                'action' => gettext("Partitioning harddisk"));
  } elsif ( $line =~ /^Creating file systems/ ) {
    %result = ( 'status' => 0, 'percent' => 3, 'task' => "task_partition",
                'action' => gettext("Creating filesystems"));
  } elsif ( $line =~ /^Calling task_mountdisks$/ ) {
    %result = ( 'status' => 0, 'percent' => 3, 'task' => "task_mountdisks",
                'action' => gettext("Mounting filesystems"));

  # Original FAI counting, no possibility to do anything here...
  } elsif ( $line =~ /^Calling task_extrbase$/ ) {
    %result = ( 'status' => 0, 'percent' => 3, 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system"));
    $percent= 3;

  # Using debootstrap for boostrapping is a bit more wise in at this point. Start at 3% and grow to approx 15%.
  } elsif ( $line =~ /^HOOK extrbase/ ) {
    %result = ( 'status' => 0, 'percent' => 3, 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system"));
  } elsif ( $line =~ /^I: Retrieving (.+)$/ ) {
    $percent= ($percent > 12) ? 12 : $percent + 0.025;
    %result = ( 'status' => 0, 'percent' => floor(3 + $percent), 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system").": ".sprintf(gettext("Retrieving %s..."), $1));
  } elsif ( $line =~ /^I: Extracting (.+)$/ ) {
    $percent= ($percent > 12) ? 12 : $percent + 0.025;
    %result = ( 'status' => 0, 'percent' => floor(3 + $percent), 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system").": ".sprintf(gettext("Extracting %s..."), $1));
  } elsif ( $line =~ /^I: Validating (.+)$/ ) {
    $percent= ($percent > 12) ? 12 : $percent + 0.025;
    %result = ( 'status' => 0, 'percent' => floor(3 + $percent), 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system").": ".sprintf(gettext("Validating %s..."), $1));
  } elsif ( $line =~ /^I: Unpacking (.+)$/ ) {
    $percent= ($percent > 12) ? 12 : $percent + 0.025;
    %result = ( 'status' => 0, 'percent' => floor(3 + $percent), 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system").": ".sprintf(gettext("Unpacking %s..."), $1));
  } elsif ( $line =~ /^I: Configuring (.+)$/ ) {
    $percent= ($percent > 12) ? 12 : $percent + 0.025;
    %result = ( 'status' => 0, 'percent' => floor(3 + $percent), 'task' => "task_extrbase",
                'action' => gettext("Bootstrapping base system").": ".sprintf(gettext("Configuring %s..."), $1));

  } elsif ( $line =~ /^Calling task_debconf$/ ) {
    %result = ( 'status' => 0, 'percent' => 15, 'task' => "task_debconf",
                'action' => gettext("Configuring base system"));
  } elsif ( $line =~ /^Calling task_prepareapt$/ ) {
    %result = ( 'status' => 0, 'percent' => 15, 'task' => "task_prepareapt",
                'action' => gettext("Preparing network install"));
  } elsif ( $line =~ /^Calling task_updatebase$/ ) {
    %result = ( 'status' => 0, 'percent' => 15, 'task' => "task_updatebase",
                'action' => gettext("Updating base system"));
  } elsif ( $line =~ /^Calling task_instsoft$/ ) {
    $task= TG_INSTALL;
    %result = ( 'status' => 0, 'percent' => 16, 'task' => "task_instsoft",
                'action' => gettext("Gathering information for package lists"));
  } elsif ( $task == TG_INSTALL && $line =~ /([0-9]+) packages upgraded, ([0-9]+) newly installed/ ) {
    $pkg_step= 69.0 / ($1 + $2) / 3.0;
    $percent= 16.0;
  } elsif ( $task == TG_INSTALL && $line =~ /Get:[0-9]+ [^ ]+ [^ ]+ ([^ ]+)/ ) {
    $percent+= $pkg_step;
    %result = ( 'status' => 0, 'percent' => floor($percent), 'task' => "task_instsoft",
                'action' => gettext("Software installation").": ".sprintf(gettext("Retrieving %s..."), $1));
  } elsif ( $task == TG_INSTALL && $line =~ /Unpacking ([^ ]+) .*from/ ) {
    $percent+= $pkg_step;
    %result = ( 'status' => 0, 'percent' => floor($percent), 'task' => "task_instsoft",
                'action' => gettext("Software installation").": ".sprintf(gettext("Extracting %s..."), $1));
  } elsif ( $task == TG_INSTALL && $line =~ /Setting up ([^ ]+)/ ) {
    $percent+= $pkg_step;
    %result = ( 'status' => 0, 'percent' => floor($percent), 'task' => "task_instsoft",
                'action' => gettext("Software installation").": ".sprintf(gettext("Configuring %s..."), $1));
  } elsif ( $line =~ /^Calling task_configure$/ ) {
    $task= TG_CONFIG;
    %result = ( 'status' => 0, 'percent' => 80, 'task' => "task_configure",
                'action' => gettext("Software installation").": ".gettext("Adapting system and package configuration"));
  } elsif ( $line =~ /^Script count: ([0-9]+)$/ ) {
    $percent= 85.0;
    $scr_step= 15.0 / $1;
  } elsif ( $line =~ /^Executing +([^ ]+): ([^\n ]+)$/ ) {
    $percent+= $scr_step;
    %result = ( 'status' => 0, 'percent' => floor($percent), 'task' => "task_configure",
                'action' => sprintf(gettext("Running script %s (%s)..."), $1, $2));
  } elsif ( $line =~ /^Calling task_savelog$/ ) {
    $percent= 100;
    %result = ( 'status' => 0, 'percent' => floor($percent), 'task' => "task_savelog",
                'action' => gettext("Installation finished"));

  # Status evaluation
  } elsif ( $line =~ /^TASKEND ([^ ]+) ([0-9]+)$/ ) {
    if ($2 != 0){
      %result = ( 'status' => $2, 'task' => "$1");
    }

  # Common errors
  } elsif ( $line =~ /^goto-error-([^:]+)$/ ) {
      %result = ( 'status' => 5, 'task' => "error-$1");
  } elsif ( $line =~ /^goto-error-([^:]+):(.*)$/ ) {
      %result = ( 'status' => 6, 'task' => "error-$1", 'action' => "$2");
  } elsif ( $line =~ /^ldap2fai-error:(.*)$/ ) {
      my $message= decode_base64("$1");
      $message =~ tr/\n/\n .\n /;
      %result = ( 'status' => 7, 'task' => "ldap2fai-error", 'action' => $message);
  } elsif ( $line =~ /^gosa-si-no-server-available$/ ) {
      %result = ( 'status' => 8, 'task' => "error-gosa-si-no-server", 'action' => gettext("No activation server available"));

  # GOto built ins
  } elsif ( $line =~ /goto-hardware-detection-start/ ) {
      if ($task != TG_WAITACTIVE){
        $task= TG_HWDETECT;
      }
      %result = ( 'status' => 0, 'task' => "goto-hardware-detection-start", 'action' => gettext("Detecting hardware"));
  } elsif ( $line =~ /goto-hardware-detection-stop/ ) {
      if ($task == TG_WAITACTIVE){
        %result = ( 'status' => 0, 'task' => "goto-activation-start", 'action' => gettext("Waiting for the system to be activated"));
      } else {
        %result = ( 'status' => 0, 'task' => "goto-hardware-detection-stop", 'action' => gettext("Inventarizing hardware information"));
      }
  } elsif ( $line =~ m/goto-activation-start/ ) {
      if ($task != TG_HWDETECT){
        %result = ( 'status' => 0, 'task' => "goto-activation-start", 'action' => gettext("Waiting for the system to be activated"));
      }
      $task= TG_WAITACTIVE;
  } elsif ( $line =~ m/goto-activation-stop/ ) {
      %result = ( 'status' => 0, 'task' => "goto-activation-stop", 'action' => gettext("System activated - retrieving configuration"));
  }

  return \%result;
}

1;

__END__

=head1 NAME

Argonaut::Utils - Calculate the progress bar for argonaut-fai-progress

=head1 SYNOPSIS

use Argonaut::Utils;

  $result = process_input($line);

=head1 Function C<process_input>

=head2 Syntax

  $result = process_input($line);

=head2 Arguments

C<$line> input line we get

=head2 Return value

 true if stream wants us to finish

=head2 Description

C<process_input> parses information from the lines and sets the progress respectively

=head1 BUGS

Please report any bugs, or post any suggestions, to the fusiondirectory mailing list fusiondirectory-users or to
<https://forge.fusiondirectory.org/projects/argonaut-agents/issues/new>

=head1 LICENCE AND COPYRIGHT

This code is part of FusionDirectory <http://www.fusiondirectory.org>

=over 3

=item Copyright (C) 2011 FusionDirectory project

=back

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

=cut

