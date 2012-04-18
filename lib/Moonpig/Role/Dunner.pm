package Moonpig::Role::Dunner;
# ABSTRACT: something that performs dunning of invoices
use Moose::Role;

use List::AllUtils 'any';
use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class event);
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(days sumof);

use namespace::autoclean;

has _last_dunning => (
  is  => 'rw',
  isa => 'HashRef',
  init_arg => undef,
  traits => [ 'Hash' ],
  predicate => 'has_ever_dunned',
  handles   => {
    last_dunning_time    => [ get => 'time' ],
  },
);

sub last_dunned_invoices {
  my ($self) = @_;
  return unless $self->has_ever_dunned;
  return @{ $self->_last_dunning->{invoices} };
}

sub last_dunned_invoice {
  my ($self) = @_;
  return unless $self->has_ever_dunned;
  return $self->_last_dunning->{invoices}->[0];
}

has dunning_frequency => (
  is => 'rw',
  isa => TimeInterval,
  default => days(3),
);

sub _should_dunn_again {
  my ($self, $invoices) = @_;

  my $overearmarked = $self->amount_overearmarked;

  # If there's nothing to pay, why would we dunn?? -- rjbs, 2012-03-26
  return unless @$invoices or $overearmarked;

  # If we never dunned before, let's! -- rjbs, 2012-03-26
  return 1 unless $self->has_ever_dunned;

  # Now things get more complicated.  We dunned once.  Do we want to dunn
  # again?  Only if (a) it's been a while or (b) the situation has changed.
  # -- rjbs, 2012-03-26
  my $since = Moonpig->env->now - $self->last_dunning_time;

  # (a) it's been a while!
  return 1 if $since > $self->dunning_frequency;

  # (b) something changed!
  return 1 if $self->_last_dunning->{overearmarked} != $overearmarked;

  my @last_invoices = $self->last_dunned_invoices;
  return 1 unless @$invoices &&  @last_invoices == @$invoices;
  return 1 if $invoices->[0]->guid ne $last_invoices[0]->guid;

  # Nope, nothing new.
  return;
}

sub perform_dunning {
  my ($self) = @_;

  my @invoices =
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         }
    grep { any { ! $_->is_abandoned } $_->all_charges }
    grep { ! $_->is_abandoned && $_->is_unpaid && $_->has_charges }
    $self->invoices;

  return unless $self->_should_dunn_again(\@invoices);

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
  my $invoice_total  = sumof { $_->total_amount } @unpaid_invoices;
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
  my ($self, $invoices_ref) = @_;

  # invoices has arrived here pre-sorted by ->perform_dunning
  my @invoices = grep { ! $_->is_internal } @$invoices_ref;

  unless (@invoices) {
    $Logger->log([
      "dunning ledger %s but not sending invoices; they're all internal",
      $self->ident,
    ]);
    return;
  }

  $Logger->log([
    "sending invoices %s to contacts of %s",
    [ map {; $_->ident } @invoices ],
    $self->ident,
  ]);

  $self->_last_dunning({
    time     => Moonpig->env->now,
    invoices => \@invoices,
    overearmarked => $self->amount_overearmarked,
  });

  $self->handle_event(event('send-mkit', {
    kit => 'invoice',
    arg => {
      subject => "PAYMENT IS DUE",

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],
      invoices     => \@invoices,
      ledger       => $self,
    },
  }));
}

1;
