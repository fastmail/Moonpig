use 5.12.0;
use warnings;

use Carp qw(confess croak);
use Moonpig::Util qw(class days dollars months to_dollars years);
use Test::More;
use Test::Routine;
use Test::Routine::Util;

use t::lib::TestEnv;

use Moonpig::Test::Factory qw(do_with_fresh_ledger);

with ('Moonpig::Test::Role::UsesStorage');

has xid => (
  isa => 'Str',
  is  => 'ro',
  default => sub { state $i = 0; $i++; "consumer:b5g1:$i"; },
);

before run_test => sub {
  Moonpig->env->reset_clock;
};

sub set_up_consumer {
  my ($self, $ledger) = @_;
  my $coupon_desc =  [ class("Coupon::FixedPercentage", "Coupon::Universal"),
                       { discount_rate => 0.25,
                         description => "blanket 25% discount",
                       }] ;

  $ledger->add_consumer_from_template("quick",
                                      { xid => $self->xid,
                                        coupon_descs => [ $coupon_desc ],
                                      });
}

test "consumer setup" => sub {
  my ($self) = @_;
  do_with_fresh_ledger({},
    sub {
      my ($ledger) = @_;
      my ($consumer) = $self->set_up_consumer($ledger);
      is(@{$consumer->coupon_array}, 1, "consumer has a coupon");
    });
};

run_me;
done_testing;
