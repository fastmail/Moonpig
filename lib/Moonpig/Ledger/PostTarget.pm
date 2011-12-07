package Moonpig::Ledger::PostTarget;
use Moose;

with(
  'Stick::Role::PublicResource',
);

use MooseX::StrictConstructor;

use Moonpig;
use Moonpig::Util qw(class);

use namespace::autoclean;

sub resource_post {
  my ($self, $arg) = @_;

  my $ledger;

  Moonpig->env->storage->txn(sub {
    my $class ||= class('Ledger');

    my $contact = class('Contact')->new({
      map {; defined $arg->{$_} ? ($_ => $arg->{$_}) : () } qw(
        first_name last_name organization
        phone_number address_lines city state postal_code country
        email_addresses 
      )
    });

    $ledger = $class->new({
      contact => $contact,
    });

    if ($arg->{consumers}) {
      my $consumers = $arg->{consumers};

      for my $xid (keys %$consumers) {
        my $template_args = $consumers->{$xid}{template_args} || {};
        $template_args->{xid} //= $xid;

        Moonpig::X->throw("xid in template_args differs from given key")
          unless $xid eq $template_args->{xid};

        $ledger->add_consumer_from_template(
          $consumers->{$xid}{template},
          $template_args,
        );
      }
    }

    Moonpig->env->save_ledger($ledger);
  });

  return $ledger;
}

1;
