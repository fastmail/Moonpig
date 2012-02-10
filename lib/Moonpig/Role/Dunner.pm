package Moonpig::Role::Dunner;
# ABSTRACT: something that performs dunning of invoices
use Moose::Role;

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class event);
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(days sumof);

use namespace::autoclean;

has _last_dunning => (
  is  => 'rw',
  isa => 'ArrayRef',
  init_arg => undef,
  traits => [ 'Array' ],
  predicate => 'has_ever_dunned',
  handles   => {
    last_dunning_time    => [ get => 1 ],
  },
);

sub last_dunned_invoices {
  my ($self) = @_;
  return unless $self->has_ever_dunned;
  return @{ $self->_last_dunning->[0] };
}

sub last_dunned_invoice {
  my ($self) = @_;
  return unless $self->has_ever_dunned;
  return $self->_last_dunning->[0][0];
}

has dunning_frequency => (
  is => 'rw',
  isa => TimeInterval,
  default => days(3),
);

sub perform_dunning {
  my ($self) = @_;

  my @invoices =
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         }
    grep { ! $_->is_abandoned && $_->is_unpaid && $_->has_charges }
    $self->invoices;

  return unless @invoices;

  # Don't send a request for payment if we sent the last request recently and
  # there has been no invoicing since then. -- rjbs, 2011-06-22
  if ($self->has_ever_dunned) {
    my $now = Moonpig->env->now;
    return if $self->last_dunned_invoice->guid eq $invoices[0]->guid
          and $now - $self->last_dunning_time <= $self->dunning_frequency;
  }

  $_->mark_closed for grep { $_->is_open } @invoices;

  # Now we have an array of closed, unpaid invoices.  Before we send anything
  # to the poor guy who is on the hook for these, let's see if we can pay any
  # with existing credits, or charge him whatever we need to, to pay this.
  $self->_autopay_invoices(\@invoices);

  $self->_send_invoice_email(\@invoices);
}

sub _autopay_invoices {
  my ($self, $invoices) = @_;

  # First, just in case we have any credits on hand, let's see if we can pay
  # them off with existing credits.
  $self->process_credits;

  # If that worked, we're done!
  return unless $self->payable_invoices;

  my @unpaid_invoices = grep { ! $_->is_paid } @$invoices;

  # Oh no, there are invoices left to pay!  How much will it take to pay it all
  # off?
  my $credit_on_hand = sumof { $_->unapplied_amount } $self->credits;
  my $invoice_total  = sumof { $_->amount_due } @unpaid_invoices;
  my $balance_needed = $invoice_total - $credit_on_hand;

  $self->_charge_for_autopay({ amount => $balance_needed });

  return;
}

sub _charge_for_autopay {
  my ($self, $arg) = @_;
  # XXX: do stuff -- rjbs, 2012-01-02
  return;
}

sub _send_invoice_email {
  my ($self, $invoices) = @_;

  # invoices has arrived here pre-sorted by ->perform_dunning

  $Logger->log([
    "sending invoices %s to contacts of %s",
    [ map {; $_->ident } @$invoices ],
    $self->ident,
  ]);

  $self->_last_dunning( [ $invoices, Moonpig->env->now ] );

  $self->handle_event(event('send-mkit', {
    kit => 'invoice',
    arg => {
      subject => "PAYMENT IS DUE",

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],
      invoices     => $invoices,
    },
  }));
}

1;
