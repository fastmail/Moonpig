use strict;
use warnings;

use Test::More;

use Moonpig::Util qw(class);
use MooseX::Role::Parameterized 0.23 ();
use Moonpig::Role::CanTransfer ();

subtest "memoization" => sub {
  plan tests => 3;
  my @class;
  push @class, class('Refund') for 1..2;
  push @class, scalar(class('Refund')) for 1..2;
  for (1..3) {
    is($class[0], $class[$_]);
  }
};

my $canTransfer = Moonpig::Role::CanTransfer->meta->generate_role(
  parameters => { transferer_type => 'bank' },
);

# Each item contains:
#  Input argument list
#  Expected class name
#  Expected methods - at least one from each role please
my @tests = (
  [ [ 'Consumer::ByTime' ],
      'MC::Consumer::ByTime',
    [ 'remaining_life' ] ],

  [ [ [ ChargeTreeContainer => Bill => { charges_handle_events => 0 } ] ],
      'MC::Bill',
    [ 'charge_tree' ] ],

  [ [ 'Consumer::ByTime', [ ChargeTreeContainer => Smitty => { charges_handle_events => 0 } ] ],
      'MC::Consumer::ByTime::Smitty',
    [ 'remaining_life', 'charge_tree' ] ],

  [ [ [ ChargeTreeContainer => Smitty => { charges_handle_events => 0 } ],
      'Consumer::ByTime' ],
      'MC::Smitty::Consumer_ByTime',
    [ 'remaining_life', 'charge_tree' ] ],
  );

for my $test (@tests) {
  my ($args, $x_name, $x_methods) = @$test;
  s/MC/Moonpig::Class/g for $x_name;
  s/MR/Moonpig::Role/g for $x_name;

  my $test_name = $x_name;
  subtest $test_name, sub {
    plan tests => 1 + @$x_methods + 1;
    my $class = class(@$args);
    is($class, $x_name);
    for my $method (@$x_methods) {
      ok($class->can($method));
    }
    is($class, class(@$args), "memoization okay");
  }
}

done_testing;
