package Moonpig::Ledger::PostTarget;
use Moose;
# ABSTRACT: necessary, dumb package for posting to the Ledger collection

with(
  'Stick::Role::PublicResource',
);

use MooseX::StrictConstructor;

use Moonpig;
use Moonpig::Util qw(class sumof);
use List::AllUtils qw(part);

use namespace::autoclean;

sub resource_get {
  my ($self) = @_;
  my @guids = Moonpig->env->storage->ledger_guids;
  return \@guids;
}

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
        phone_book address_lines city state postal_code country
        email_addresses 
      )
    });

    $ledger = $class->new({
      contact => $contact,
    });

    # We probably *should* do this in (after Ledger::BUILD) but we can't
    # because save is fatal outside a transaction and "in-a-transaction-p"
    # doesn't have any sort of public predicate.  Until we address that, we'll
    # do the save here.  It's vital so that during invoicing, InvoiceCharges
    # can find their owner object. -- rjbs, 2012-02-29
    $ledger->save;

    # XXX: This should be possible via public means.  We need to bypass the
    # save queue because MySQL does not have deferred FK resolution, and if we
    # try to queue a job for a not-yet-saved ledger, it will die immediately
    # instead of being safely resolved at COMMIT-time. -- rjbs, 2012-04-05
    Moonpig->env->storage->_store_ledger($ledger);

    if ($arg{consumers}) {
      my $consumers = $arg{consumers};

      for my $xid (keys %$consumers) {
        my $this = $consumers->{$xid};

        my %extra = map {; $_ => 1 } keys %$this;
        delete @extra{qw(template template_args)};
        if (keys %extra) {
          Moonpig::X->throw({
            ident   => "unknown args in consumer hashes",
            payload => { args => [ keys %extra ] },
          });
        }

        my $template_args = $this->{template_args} || {};
        $template_args->{xid} //= $xid;

        Moonpig::X->throw("xid in template_args differs from given key")
          unless $xid eq $template_args->{xid};

        $ledger->add_consumer_from_template(
          $this->{template},
          $template_args,
        );
      }
    }

    if ($arg{old_payment_info}) {
      $ledger->current_invoice->mark_internal;

      # Not worrying about closed/open.  The ledger is brand new.  We just find
      # invoices that need money, then provide it.
      my @charges =
        map  { $_->all_charges }
        grep { $_->is_unpaid   }
        $ledger->invoices_without_quotes;

      my %is_active = map { $_->guid => 1 } $ledger->active_consumers;

      my $total    = sumof { $_->amount } @charges;
      my $pay_info = $arg{old_payment_info};

      $ledger->add_credit(
        class('Credit::Imported::Refundable'),
        {
          amount => $total,
          old_payment_info => $pay_info,
        },
      );
    }

    $ledger->heartbeat;

    if ($arg{old_payment_info}) {
      # This really shouldn't be reachable.  If we have old_payment_info, we
      # should have just created enough cash to cover everything.  But it also
      # shouldn't hurt.  It could catch non-application, or second invoices,
      # or... who knows what. -- rjbs, 2012-04-18
      my @internal_invoices = grep { $_->is_internal } $ledger->invoices_without_quotes;
      Moonpig::X->throw("internal invoice was created and not paid")
        if @internal_invoices and grep { ! $_->is_paid } @internal_invoices;
    }
  });

  return $ledger;
}

1;
