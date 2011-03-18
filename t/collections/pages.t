#!/usr/bin/env perl
use strict;
use warnings;
use Test::More;
use Test::Fatal;
use Test::Routine;
use Test::Routine::Util -all;
use Moonpig::Env::Test;
use Moonpig::Util qw(class dollars);

with(
  't::lib::Factory::Ledger',
);

has ledger => (
  is => 'ro',
  does => 'Moonpig::Role::Ledger',
  lazy => 1,
  default => sub { $_[0]->test_ledger },
  clearer => 'scrub_ledger',
  handles => [ qw(refund_collection) ],
);

before run_test => sub {
  my ($self) = @_;

  $self->scrub_ledger;
};

sub refund {
  my ($self, $amount) = @_;
  class("Refund")->new({
    ledger => $self->ledger,
    amount => $amount || dollars(1),
  });
}

sub ids {
  join ", " => sort map $_->guid, @_;
}

test "page" => sub {
  my ($self) = @_;

  my $credit = $self->ledger->add_credit(
    class('Credit::Simulated', 't::Refundable::Test'),
    { amount => dollars(5_000) },
  );

  my @r;
  is($self->ledger->refund_collection->_pages, 0);

  for (1..30) {
    push @r, my $next_refund = $self->ledger->add_refund(class('Refund'));
    $self->ledger->create_transfer({
      type => 'credit_application',
      from => $credit,
      to => $next_refund,
      amount => dollars(10) + $_ * dollars(1.01),
    });
    is($self->ledger->refund_collection->_pages,     int($_ / 20))
      if $_ % 20 == 0;
    is($self->ledger->refund_collection->_pages, 1 + int($_ / 20))
      if $_ % 20 != 0;
  };

  {
    my @page1 = $self->refund_collection->_page(1);
    my @page2 = $self->refund_collection->_page(2);
    my @page3 = $self->refund_collection->_page(3);

    is(@page1, 20, "page 1 has 20/30 items");
    is(@page2, 10, "page 2 has 10/30 items");
    is(@page3,  0, "page 3 is empty");

    is(ids(@page1, @page2), ids(@r), "pages 1+2 have all 30 items");
  }

  {
    for (1..4) {
      my @page = $self->refund_collection->_page($_, 7);
      is(@page, 7, "page $_ has 7/7 items");
    }
    my @page = $self->refund_collection->_page(5, 7);
    is(@page, 2, "page 5 has 2/7 items");
  }

  {
    my $c = $self->refund_collection;
    $c->default_page_size(7);
    for (1..4) {
      my @page = $c->_page($_);
      is(@page, 7, "page $_ has 7/7 items");
    }
    my @page = $c->_page(5);
    is(@page, 2, "page 5 has 2/7 items");
  }

};


run_me;
done_testing;
