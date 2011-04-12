package Fauxbox::Moonpig::Env;
use Moose;
extends 'Moonpig::Env::Test';

use Email::Sender::Transport::Maildir;

sub build_email_sender {
  Email::Sender::Transport::Test->new({
    dir => File::Spec->catdir($ENV{FAUXBOX_ROOT}, 'Maildir'),
  });
}

1;
