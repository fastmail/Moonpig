package Moonpig::Ledger::PostTarget;
use Moose;

with(
  'Stick::Role::PublicResource',
);

use Moonpig;
use Moonpig::Util qw(class);

use namespace::autoclean;

sub resource_post {
  my ($self, $arg) = @_;

  my $ledger;

  Moonpig->env->storage->txn(sub {
    my $class ||= class('Ledger');

    my $contact = class('Contact')->new({
      name            => $arg->{name},
      email_addresses => $arg->{email_addresses},
    });

    $ledger = $class->new({
      contact => $contact,
    });

    if ($arg->{consumers}) {
      my $consumers = $arg->{consumers};

      for my $xid (keys %$consumers) {
        $ledger->add_consumer_from_template(
          $consumers->{$xid}{template},
          {
            xid => $xid,
          },
        );
      }
    }

    Moonpig->env->save_ledger($ledger);
  });

  return $ledger;
}

1;
