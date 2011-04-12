package Fauxbox::Moonpig::Env;
use Moose;
extends 'Moonpig::Env::Test';

use Moonpig::Logger '$Logger';

use Email::Sender::Transport::Maildir;
use Email::Sender::Transport::SMTP;

# I would just use this instead of the copied and pasted "handle_send_email"
# method below, but I want to send real mail and maildir mail, and we don't
# have a muxing mailer. -- rjbs, 2011-04-12
#
#sub build_email_sender {
#  Email::Sender::Transport::Maildir->new({
#    dir => File::Spec->catdir($ENV{FAUXBOX_ROOT}, 'Maildir'),
#  });
#}

sub handle_send_email {
  my ($self, $event, $arg) = @_;

  # XXX: validate email -- rjbs, 2010-12-08

  my @senders = (
    Email::Sender::Transport::SMTP->new({
      helo => 'moonpig.fauxbox.com',
    }),
    Email::Sender::Transport::Maildir->new({
      dir => File::Spec->catdir($ENV{FAUXBOX_ROOT}, qw(var Maildir)),
    }),
  );

  for my $sender (@senders) {
    $Logger->log_debug([ 'sending mail through %s', blessed $sender ]);
    $sender->send_email(
      $event->payload->{email},
      $event->payload->{env},
    );
  }
}

my $THIS = __PACKAGE__->new;
sub import {
  Moonpig->set_env($THIS)
};

1;
