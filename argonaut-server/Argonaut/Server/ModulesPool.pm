package Argonaut::Server::ModulesPool;

use strict;
use diagnostics;
use POE qw( Component::Pool::Thread );
use threads::shared;
use Module::Pluggable search_path => 'Argonaut::Server::Modules', require => 1;

sub rclone {
  my $ref = shift;
  my $type = ref $ref;
  if( $type eq 'HASH' ) {
    return { map rclone( $_ ), %{ $ref } };
  }
  elsif( $type eq 'ARRAY' ) {
    return [ map rclone( $_ ),@{ $ref } ];
  }
  elsif( $type eq 'REF' ) {
    return \ rclone( $$ref );
  }
  else {
    print "ignoring type '$type'\n" if $type ne '';
    return $ref;
  }
}

sub thread_sendobject {
  my $object  = shift;
  my $blob :shared = shared_clone({'class' => ref $object});
  $blob->{object} = shared_clone({ %$object }); # Copying object as a hash
  return $blob;
}

sub thread_getobject {
  my $blob = shift;
  my $object  = rclone($blob->{object});
  my $class   = ref $object;
  bless $object, $blob->{class};
  return $object;
}

sub new {
  my ($class, %args) = @_;

  my $self = bless \%args, $class;

  # This creates the threadpool which does the actual work.  The entry point
  # for the actual threads themselves is the query_database function.
  $self->{session} = POE::Component::Pool::Thread->new (
    MinFree       => 2,
    MaxFree       => 5,
    MaxThreads    => 15,
    StartThreads  => 5,
    EntryPoint    => \&module_thread_entry_point,
    CallBack      => \&module_thread_result_handler,
    Name          => "$self",
    inline_states => {
      do      => sub {
        my ($kernel, $heap, $sender, $object, $taskid, $args) =
            @_[ KERNEL, HEAP, SENDER, ARG0 .. $#_ ];
        $heap->{sender} = $sender;

        print "Launching thread for task $taskid, action '".$object->{action}."'\n";

        $args ||= [];
        $object->{taskid} = $taskid;

        $kernel->yield(run => thread_sendobject($object), shared_clone($args));
      },
    }
  );

  return "$self";
}

sub module_thread_entry_point {
  my ($o, $args) = @_;
  my $object = thread_getobject($o);
  my $res :shared;
  eval {
    $res = shared_clone($object->do_action($args));
  };
  if ($@) {
    return ($@, undef, thread_sendobject($object));
  };
  return (undef, $res, thread_sendobject($object));
}

=pod
$object->{task} might contain the following keys:
substatus : new substatus of the task
handler : 1 if the task handler should be filled
=cut
sub module_thread_result_handler {
  my ($kernel, $error, $result, $o) = @_[ KERNEL, ARG0..$#_];
  my $object = thread_getobject($o);
  if (defined $error) {
    $kernel->post( $_[HEAP]->{sender}, "set_task_error", $object->{taskid}, $error);
    return;
  }
  if (defined $object->{task}) {
    if (defined $object->{task}->{substatus}) {
      $kernel->post( $_[HEAP]->{sender}, "set_task_substatus", $object->{taskid}, $object->{task}->{substatus}, $object->{task}->{progress});
    }
    if ($object->{task}->{handler}) {
      $kernel->post( $_[HEAP]->{sender}, "set_task_handler", $object->{taskid}, $object);
    }
  }
  if (defined $object->{launch_actions}) {
    foreach my $action (@{$object->{launch_actions}}) {
      $kernel->post( $_[HEAP]->{sender}, "add", undef, undef, @$action);
    }
  }
  $kernel->post( $_[HEAP]->{sender}, "set_task_result", $object->{taskid}, $result);
}

1;

__END__

