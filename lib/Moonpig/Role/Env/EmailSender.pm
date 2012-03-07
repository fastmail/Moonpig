package Moonpig::Role::Env::EmailSender;
# ABSTRACT: a Moonpig environment that sends its own mail

use Moose::Role;

use MooseX::StrictConstructor;

use namespace::autoclean;

use Email::Simple;
use JSON;
use Email::Sender::Transport::Test;

has email_sender => (
  is   => 'ro',
  does => 'Email::Sender::Transport',
  builder => 'build_email_sender',
);

sub build_email_sender {
  ...
}

sub process_email_queue {
  my ($self) = @_;

  my $count = 0;

  $self->storage->iterate_jobs('send-email', sub {
    my ($job) = @_;
    my $email = Email::Simple->new($job->payload('email'));

    my $env = JSON->new->decode( $job->payload('env') );
    Moonpig->env->send_email($email, $env);
    $job->mark_complete;
    $count++;
  });

  return $count;
}

sub send_email {
  my ($self, $email, $env) = @_;
  $self->email_sender->send_email($email, $env);
}

1;
