package Argonaut::Server::ModulesPool;

use strict;
use POE qw( Component::Pool::Thread );
use threads::shared;

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
    Name          => "$self";
    inline_states => {
      do      => sub {
        my ($kernel, $heap, $sender, $object, $taskid, $args) =
            @_[ KERNEL, HEAP, SENDER, ARG0 .. $#_ ];

        $args ||= [];
        share($object);
        share($args);
        $heap->{sender} = $sender;

        $kernel->yield(run => ref $object, $object, $taskid, $args);
      },
    }
  );

  return "$self";
}

sub module_thread_entry_point {
  my ($module, $object, $taskid, $args) = @_;
  bless $object, $module;
  my $res;
  eval {
    $object->{taskid} = $taskid;
    $res = $object->do_action($args);
  };
  if ($@) {
    return [$@, undef, $object];
  };
  return [undef, $res, $object];
}

=pod
$object->{task} might contain the following keys:
substatus : new substatus of the task
handler : 1 if the task handler should be filled
=cut
sub module_thread_result_handler {
  my ($kernel, $array) = @_[ KERNEL, ARG0];
  my ($error, $result, $object) = @$array;
  if (defined $error) {
    $kernel->post( $_[HEAP]->{sender}, "set_task_error", $object->{taskid}, $error);
    return;
  }
  if (defined $object->{task}) {
    if (defined $object->{task}->{substatus}) {
      $kernel->post( $_[HEAP]->{sender}, "set_task_substatus", $object->{taskid}, $object->{task}->{substatus}, $object->{task}->{progress});
    }
    # TODO : gérer le handler
  }
  $kernel->post( $_[HEAP]->{sender}, "set_task_result", $object->{taskid}, $result);
}
