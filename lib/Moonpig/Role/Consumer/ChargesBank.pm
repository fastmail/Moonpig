package Moonpig::Role::Consumer::ChargesBank;
# ABSTRACT: a consumer that can issue journal charges to a bank
use Moose::Role;
with(
  'Moonpig::Role::Consumer',
);

use Moonpig::Trait::Copy;
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(class);
use MooseX::Types::Moose qw(ArrayRef);

use namespace::autoclean;

has extra_journal_charge_tags => (
  is  => 'ro',
  isa => ArrayRef,
  default => sub { [] },
  traits => [ qw(Copy) ],
);

sub journal_charge_tags {
  my ($self) = @_;
  return [ $self->xid, @{$self->extra_journal_charge_tags} ]
}

# When the object has less than this long to live, it will
# start posting low-balance events to its successor, or to itself if
# it has no successor
has old_age => (
  is => 'ro',
  required => 1,
  isa => TimeInterval,
  traits => [ qw(Copy) ],
);

has bank => (
  reader => 'bank',
  writer => '_set_bank',
  does   => 'Moonpig::Role::Bank',
  traits => [ qw(SetOnce) ],
  predicate => 'has_bank',
);

before _set_bank => sub {
  my ($self, $bank) = @_;

  unless ($self->ledger->guid eq $bank->ledger->guid) {
    confess sprintf(
      "cannot associate consumer from %s with bank from %s",
      $self->ledger->ident,
      $bank->ledger->ident,
    );
  }
};

sub unapplied_amount {
  my ($self) = @_;
  return $self->has_bank ? $self->bank->unapplied_amount : 0;
}

# when copying this consumer to another ledger, copy its bank as well
after copy_subcomponents_to__ => sub {
  my ($self, $target, $copy) = @_;
  $self->move_bank_to__($copy);
};

# "Move" my bank to a different consumer.  This will work even if the
# consumer is in a different ledger.  It works by entering a charge to
# my bank for its entire remaining funds, then creating a credit in
# the recipient consumer's ledger and using the credit to set up a
# fresh bank for the recipient.
sub move_bank_to__ {
  my ($self, $new_consumer) = @_;
  my $amount = $self->unapplied_amount;
  return if $amount == 0;

  my $ledger = $self->ledger;
  my $new_ledger = $new_consumer->ledger;
  Moonpig->env->storage->do_rw(
    sub {
      $ledger->current_journal->charge({
        desc        => sprintf("Transfer management of '%s' to ledger %s",
                               $self->xid, $new_ledger->guid),
        from        => $self->bank,
        to          => $self,
        date        => Moonpig->env->now,
        amount      => $amount,
        tags        => [ @{$self->journal_charge_tags}, "transient" ],
      });
      my $credit = $new_ledger->add_credit(
        class('Credit::Transient'),
        {
          amount               => $amount,
          source_bank_guid     => $self->bank->guid,
          source_consumer_guid => $self->guid,
          source_ledger_guid   => $ledger->guid,
        });
      my $transient_invoice = class("Invoice")->new({
         ledger      => $new_ledger,
      });
      my $charge = $transient_invoice->add_charge(
        class('InvoiceCharge::Bankable')->new({
          description => sprintf("Transfer management of '%s' from ledger %s",
                                 $self->xid, $ledger->guid),
          amount      => $amount,
          consumer    => $new_consumer,
          tags        => [ @{$new_consumer->journal_charge_tags}, "transient" ],
        }),
       );
      $new_ledger->apply_credits_to_invoice__(
        [{ credit => $credit,
           amount => $amount }],
        $transient_invoice);
    });
}
1;
