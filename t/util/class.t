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
#  Expected roles
my @tests = (
  [ [ 'Consumer::ByTime' ],
      'MC::Consumer::ByTime',
    [ 'MR::Consumer::ByTime' ] ],

  [ [ [ CanTransfer => Bill => { transferer_type => 'bank' } ] ],
      'MC::Bill',
    [ 'MR::CanTransfer' ] ],

  [ [ 'Consumer::ByTime', [ CanTransfer => Smitty => { transferer_type => 'bank' } ] ],
      'MC::Consumer::ByTime::Smitty',
    [ 'MR::CanTransfer', 'MR::Consumer::ByTime' ] ],

  [ [ [ CanTransfer => cantransfer => { transferer_type => 'bank' } ],
    'Consumer::ByTime' ],
      'MC::cantransfer::Consumer_ByTime',
    [ 'MR::CanTransfer', 'MR::Consumer::ByTime' ] ],
);

for my $test (@tests) {
  my ($args, $x_name, $x_roles) = @$test;
  s/MC/Moonpig::Class/g for $x_name, @$x_roles;
  s/MR/Moonpig::Role/g for $x_name, @$x_roles;

  my $test_name = join ", ", @$args;
  subtest $test_name, sub {
    plan tests => 1 + @$x_roles + 1;
    my $class = class(@$args);
    is($class, $x_name);
    for my $role (@$x_roles) {
      ok($class->does($role));
    }
    is($class, class(@$args), "memoization okay");
  }
}

done_testing;
