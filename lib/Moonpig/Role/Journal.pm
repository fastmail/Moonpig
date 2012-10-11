package Moonpig::Role::Journal;
# ABSTRACT: a journal of how consumers funds are spent

use Carp qw(croak);
use Moonpig::Util qw(class);
use Moose::Role;

use Moonpig::Logger '$Logger';

with(
  'Moonpig::Role::HasLineItems',
  'Moonpig::Role::CanTransfer' => { transferer_type => "journal" },
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::HasGuid',
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
);

use Stick::Publisher 0.307;
use Stick::Publisher::Publish 0.307;

use namespace::autoclean;

sub charge_role { 'JournalCharge' }

sub accepts_line_item {
  my ($self, $line_item) = @_;
  $line_item->does("Moonpig::Role::JournalCharge");
}

# from: source of money transfer
# to: destination of money transfer
# amount: amount of transfer
# description: charge descriptiopn
# tags: what tags to put on the charge
# when: when to record charge (optional)
sub charge {
  my ($self, $args) = @_;

  { my $FAIL = "";
    for my $reqd (qw(from to amount description tags consumer)) {
      $FAIL .= __PACKAGE__ . "::charge missing required '$reqd' argument"
        unless $args->{$reqd};
    }
    croak $FAIL if $FAIL;
  }

  # create transfer
  $self->ledger->transfer({
    amount => int($args->{amount}), # Round in favor of customer
    from   => $args->{from},
    to     => $args->{to},

    skip_funds_check => $args->{skip_funds_check},
  });

  my $charge = $self->charge_factory->new({
    consumer    => $args->{consumer},
    description => $args->{description},
    amount => $args->{amount},
    date => $args->{when} || Moonpig->env->now(),
    tags => $args->{tags},
  });

  $self->add_charge($charge);

  $Logger->log([
    "adding charge for %s tagged %s",
    $charge->amount,
    join(q{ }, @{ $args->{tags} }),
  ]);

  return $charge;
}

publish _recent_activity => {
  -path => 'recent-activity',
  -http_method => 'get',
} => sub {
  my ($self) = @_;
  my @items = $self->all_items;
  # fencepost? maybe.  just want to get something working atm -- rjbs,
  # 2012-10-10
  splice @items, 0, (@items - 200) if @items > 200;

  return {
    items => [
      map {; {
        date   => $_->date,
        amount => $_->amount,
        description => $_->description,
      } } @items
    ],
  };
};

sub _class_subroute { return }

sub charge_factory {
  class('JournalCharge');
}

1;
