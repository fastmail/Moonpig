package Moonpig::Ledger::PostTarget;
use Moose;

with(
  'Stick::Role::PublicResource',
);

use MooseX::StrictConstructor;

use Moonpig;
use Moonpig::Util qw(class sumof);
use List::AllUtils qw(part);

use namespace::autoclean;

sub resource_post {
  my ($self, $received_arg) = @_;

  my $ledger;

  Moonpig->env->storage->txn(sub {
    my $class ||= class('Ledger');
    my %arg = %$received_arg;

    my $contact_arg = delete $arg{contact};
    my $contact = class('Contact')->new({
      map {; defined $contact_arg->{$_} ? ($_ => $contact_arg->{$_}) : () } qw(
        first_name last_name organization
        phone_number address_lines city state postal_code country
        email_addresses 
      )
    });

    $ledger = $class->new({
      contact => $contact,
    });

    if ($arg{consumers}) {
      my $consumers = $arg{consumers};

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

    if ($arg{pay_as_imported}) {
      # Not worrying about closed/open.  The ledger is brand new.  We just find
      # invoices that need money, then provide it.
      my @charges =
        map  { $_->all_charges }
        grep { $_->is_unpaid   }
        $ledger->invoices;

      my %is_active = map { $_->guid => 1 } $ledger->active_consumers;

      # We want to pay off the invoices generated in setting up this new
      # consumer.  The active head (likely to be pro-rated) for each chain is
      # not refundable, because it is active service.  The rest of the chain
      # is refundable in some way. -- rjbs, 2012-02-24
      my ($act_c, $inact_c) = part { $is_active{ $_->owner_guid } } @charges;
      my $r_amount = sumof { $_->amount } @$inact_c;
      my $n_amount = sumof { $_->amount } @$act_c;

      $self->add_credit(
        class('Credit::Imported'),
        { amount => $n_amount },
      );

      $self->add_credit(
        class('Credit::Imported::Refundable'),
        { amount => $r_amount },
      );
    }

    $ledger->heartbeat;

    Moonpig->env->save_ledger($ledger);
  });

  return $ledger;
}

1;
