use Test::Routine;

use Moonpig::Env::Test;

use Carp qw(confess croak);
use Moonpig::Events::Handler::Code;
use Moonpig::Util -all;
use Test::Deep qw(cmp_deeply);
use Test::Fatal;
use Test::More;
use Test::Routine::Util;
use Try::Tiny;

with(
  't::lib::Factory::Ledger',
);

use t::lib::ConsumerTemplateSet::Test;

test "consumer from template" => sub {
  my ($self) = @_;

  my $ledger = $self->test_ledger;

  my $c = $ledger->add_consumer_from_template(
    'boring',
    { make_active => 1 },
  );

  ok(
    $c->does('Moonpig::Role::Consumer::ByTime'),
    "we got a consumer with the roles from the template",
  );

  is(
    $c->charge_description,
    'boring test charge',
    "...and the charge description we expected",
  );

  ok(
    same_object($c, $c->ledger->active_consumer_for_xid( $c->xid )),
    "and things are registered sanely by xid, etc.",
  );
};

run_me;
done_testing;
