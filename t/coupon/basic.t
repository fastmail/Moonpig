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
                         description => "Joe's discount",
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
      my @charges = $ledger->current_invoice->all_charges;
      is(@charges, 1, "one charge");
#      is(@charges, 2, "two charges (1 + 1 line item)");

      is($charges[0]->amount, dollars(75), "true charge amount: \$75");
      SKIP: { skip "line items unimplemented", 2;
        is($charges[1]->amount, 0, "line item amount: 0mc");
        like($charges[1]->description, qr/Joe's discount/, "line item description");
        like($charges[1]->description, qr/25%/, "line item description amount");
      }
    });
};

run_me;
done_testing;
