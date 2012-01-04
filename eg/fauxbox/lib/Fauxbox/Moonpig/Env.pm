package Fauxbox::Moonpig::Env;
use Moose;
extends 'Moonpig::Env::Test';

use Moonpig::Logger '$Logger';

use Email::Sender::Transport::Maildir;
use Email::Sender::Transport::SMTP;

sub send_email {
  my ($self, $email, $env) = @_;

  # XXX: validate email -- rjbs, 2010-12-08

  # Too bad we don't have a muxing transport. -- rjbs, 2011-04-14
  my @senders = (
    $ENV{FAUXBOX_NO_SMTP} ? () : (
      Email::Sender::Transport::SMTP->new({
        helo => 'moonpig.fauxbox.com',
      })),
    Email::Sender::Transport::Maildir->new({
      dir => File::Spec->catdir($ENV{FAUXBOX_ROOT}, qw(var Maildir)),
    }),
  );

  for my $sender (@senders) {
    $Logger->log_debug([ 'sending mail through %s', blessed $sender ]);
    $sender->send_email($email, $env);
  }
}

my $THIS = __PACKAGE__->new;
sub import {
  Moonpig->set_env($THIS)
};

sub extra_share_roots {
  return File::Spec->catdir($ENV{FAUXBOX_ROOT}, 'share');
}

sub default_from_email_address {
  Email::Address->new(
    'Moonpig',
    'moonpig@fauxbox.com',
  );
}

1;
