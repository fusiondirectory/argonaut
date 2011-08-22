package OPSI;

use Exporter;
@ISA = ("Exporter");

use strict;
use warnings;

use Switch;
use Net::LDAP;
use Net::LDAP::Util qw(:escape);
use JSON::RPC::Client;

sub get_module_info {
  return "Automatic Windows Installation";
};

my $admin;
my $password;
my $server;
my $lang;
my $sclient="";

my $cfg_defaults = {
  # 'dflt_init' => [ my	$dflt_init, 'install' ], # 'install', 'fallback';;
  'admin'  => [ \$admin,  'admin' ],
  'password'  => [ \$password,  '' ],
  'server' => [ \$server, 'localhost' ],
  'lang' => [ \$lang, 'de' ],
};

sub get_config_sections {
  return $cfg_defaults;
}

# Check if this module should handle this client
# return 1 if this is the case, 0 otherwise
sub has_pxe_config {
  # Initialize opsi stuff
  my $opsi_url= "https://$admin:$password\@$server:4447/rpc";
  my $opsi_client = new JSON::RPC::Client;

  my ($filename) = shift || return undef;

  &main::daemon_log("ch $$: got filename ${filename}\n");

  # Extract MAC from PXE filename      
  my $mac = $filename;                 
  $mac =~ tr/-/:/;
  $mac = substr( $mac, -1*(5*3+2) ); 

  # Load actions
  my $callobj = {
    method  => 'getClientIdByMac',
    params  => [$mac],
    id  => 1,
  };
  my $res = $opsi_client->call($opsi_url, $callobj);
  my $state= 0;

  if($res) {
    if($res->is_error) {
      &main::daemon_log("ch $$: Error : ". $res->error_message."\n");
    } else {
      my $client = $res->result;
      &main::daemon_log("ch $$: Found OPSI configuration for client with MAC ${mac}\n");
      return 1;
    }
  } else {
    &main::daemon_log("ch $$: Error : ". $opsi_client->status_line."\n");
  }

  # Move result
  return 0;
}

# Do everything that is needed, i.e. write the pxelinux.cfg file
sub get_pxe_config {
# Initialize opsi stuff
  my $opsi_url= "https://$admin:$password\@$server:4447/rpc";
  my $opsi_client = new JSON::RPC::Client;

  my ($filename) = shift || return undef;
  my $result = undef;

  # Extract MAC from PXE filename      
  my $mac = $filename;                 
  $mac =~ tr/-/:/;
  $mac = substr( $mac, -1*(5*3+2) ); 

  # Load actions
  my $callobj = {
    method  => 'getClientIdByMac',
    params  => [$mac],
    id  => 1,
  };
  my $res = $opsi_client->call($opsi_url, $callobj);
  my $state= 0;
  my $status= "localboot";
  my $kernel = "kernel opsi-install";
  my $cmdline;
  my $product= "";

  if($res) {
    if($res->is_error) {
      &main::daemon_log("ch $$: Error : ". $res->error_message."\n");
    } else {
      $sclient=$res->result;
      $callobj = { method  => 'getNetBootProductStates_hash', params  => [ $sclient ], id  => 2, };
      my $res2 = $opsi_client->call($opsi_url, $callobj);
      if($res2) {
        if($res2->is_error) {
          &main::daemon_log("ch $$: Error : ". $res2->error_message."\n");
        } else {
          foreach my $element (@{$res2->result->{$sclient}}){
          if(
            $element->{'actionRequest'} ne '' &&
            $element->{'actionRequest'} ne 'undefined' &&
            $element->{'actionRequest'} ne 'none' ) 
          {
            $state= 1;
            $status= "install";
            $product= "product=".$element->{'productId'};
            last;
          }
        }
      }
    } else {
      &main::daemon_log("ch $$: Error : ". $opsi_client->status_line."\n");
    }

    if ( $state ) {
      # Installation requested
      my $service= "";
      my $pckey= "";

      # Load pc key
      $callobj = { method  => 'getOpsiHostKey', params  => [ $sclient ], id  => 4, };
      $res = $opsi_client->call($opsi_url, $callobj);
      if (defined $res->result){
        $pckey= "pckey=".$res->result;
        &main::daemon_log( "setting pckey for $sclient\n" );
      } else {
        &main::daemon_log( "no pc key for $sclient found\n" );
      }

      # Load depot server for this client
      $callobj = { method  => 'getDepotId', params  => [ $sclient ], id  => 5, };
      $res = $opsi_client->call($opsi_url, $callobj);
      if (defined $res->result){
        $service= "service=".$res->result;
        &main::daemon_log( "setting depot server for $sclient to $service\n" );
      } else {
        &main::daemon_log( "no depot server for $sclient defined\n" );
      }
      $cmdline = "noapic lang=$lang ramdisk_size=175112 init=/etc/init initrd=opsi-root.gz reboot=b video=vesa:ywrap,mtrr $service $pckey vga=791 quiet splash $product";
    } else {
      # Localboot
      $kernel = 'localboot 0';
      $cmdline = '';
    }
  }
} else {
  &main::daemon_log("ch $$: Error : ". $opsi_client->status_line."\n");
}


&main::daemon_log( "$filename - PXE status: $status\n" );
my $code = &main::write_pxe_config_file( $sclient, $filename, $kernel, $cmdline );
if ( $code == 0) {
  return time;
} 
if ( $code == -1) {
  &main::daemon_log( "$filename - unknown state: $status\n" );
}

# Return our result
return $result;
}

1;

# vim:ts=2:sw=2:expandtab:shiftwidth=2:syntax:paste
