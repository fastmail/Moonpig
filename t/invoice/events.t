use Test::Routine;
use Test::Routine::Util -all;
use Test::More;
use Test::Deep qw(cmp_deeply superhashof ignore re);
use Test::Fatal;

use t::lib::TestEnv;
use Data::Dumper::Concise;

with(
  'Moonpig::Test::Role::LedgerTester',
);
use Moonpig::Test::Factory qw(do_with_fresh_ledger);
use Moonpig::Util qw(class days dollars event);

use namespace::autoclean;

my $guid_re = re('^[A-F0-9]{8}(-[A-F0-9]{4}){3}-[A-F0-9]{12}$');
my $date_re = re('^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\d$');

test "invoice events are created correctly" => sub {
  my ($self) = @_;

  my ($guid, $ledger);
  my $num_expected_events = 0;

  subtest "create invoice" => sub {
    do_with_fresh_ledger({ c => { template => 'dummy' }}, sub {
      ($ledger) = @_;
      $guid = $ledger->guid;

      my $invoice = $ledger->current_invoice;
      $invoice->add_charge(
        class(qw(InvoiceCharge))->new({
          description => 'test charge',
          amount      => dollars(5),
          consumer    => $ledger->get_component('c'),
        }),
      );
      $invoice->mark_closed;
      $num_expected_events++;

      ok($invoice->is_payable, "creates new open invoice");
      ok($invoice->isnt_quote, "new invoice is not a quote");

      my $items = get_events($guid);
      is(@$items, $num_expected_events, "have $num_expected_events event");

      my $last = pop @$items;
      is($last->{event}, "invoice.invoiced", "last event is invoice.invoiced");
    });
  };

  subtest "create quote" => sub {
    Moonpig->env->storage->do_with_ledger($guid, sub {
      ($ledger) = @_;
      $guid = $ledger->guid;

      my $q = $ledger->quote_for_new_service(
        { template => 'quick' },
        { xid => "test:A" },
        days(3),
      );
      $num_expected_events++;

      ok($q, "made quote");
      $ledger->name_component("q", $q);

      my $items = get_events($guid);
      is(@$items, $num_expected_events, "created one event");

      my $last = pop @$items;
      is($last->{event}, "quote.created", "event is quote.created");
    });
  };

  subtest "execute quote" => sub {
    Moonpig->env->storage->do_with_ledger($guid, sub {
        my ($ledger) = @_;

        # Executing quote doesn't add an event
        my $q = $ledger->get_component('q');
        $q->execute;

        ok($q->is_executed, "quote was executed");
        ok($q->isnt_quote, "quote is now an invoice");

        my $items = get_events($guid);
        is(@$items, $num_expected_events, "still have $num_expected_events event");

        my $last = pop @$items;
        is($last->{event}, "quote.executed", "event is quote.executed");
      });
  };

  subtest "do dunning" => sub {
    Moonpig->env->storage->do_with_ledger($guid, sub {
        my ($ledger) = @_;

        $ledger->perform_dunning;
        $num_expected_events++;

        my $items = get_events($guid);
        is(@$items, $num_expected_events, "still have $num_expected_events event");

        my $last = pop @$items;
        is($last->{event}, "dunning", "event is dunning");
        $self->assert_n_deliveries(1, "invoice");
      });
  };

  subtest "add credit" => sub {
    Moonpig->env->storage->do_with_ledger($guid, sub {
      my ($ledger) = @_;

      $ledger->add_credit(
        class(qw(Credit::Simulated)),
        {
          amount => dollars(100)
        },
      );
      $num_expected_events++;

      my $items = get_events($guid);
      is(@$items, $num_expected_events, "have $num_expected_events events");

      my $last = pop @$items;
      is($last->{event}, "credit.paid", "last event is credit.paid");
    });
  };

  subtest "pay quote" => sub {
    Moonpig->env->storage->do_with_ledger($guid, sub {
        my ($ledger) = @_;

        my $q = $ledger->get_component('q');
        $q->mark_paid;
        $q->handle_event(event('paid'));
        $num_expected_events++;

        my $items = get_events($guid);
        is(@$items, $num_expected_events, "have $num_expected_events events");

        my $last = pop @$items;
        is($last->{event}, "invoice.paid", "last event is invoice.paid");
      });
  };

  subtest "events have right data" => sub {
    Moonpig->env->storage->do_with_ledger($guid, sub {
      my ($ledger) = @_;

      my $items = get_events($guid);

      my %need_amounts = (
        'invoice.invoiced'  => 1,
        'quote.created'     => 1,
        'quote.executed'    => 1,
        'credit.paid'       => 1,
        'dunning'           => 1,
        'invoice.paid'      => 0,
      );

      for my $event (@$items) {
        my $type = $event->{event};
        cmp_deeply(
          $event,
          superhashof({
            date  => $date_re,
            guid  => $guid_re,
          }),
          "$type has generic data"
        );

        if ($need_amounts{$type}) {
          cmp_deeply(
            $event,
            superhashof({
              amount => re(qr/[0-9]+/),
            }),
            "$type has amount"
          );
        }
      }
    });
  };
};

run_me;
done_testing;

sub get_events {
  my ($guid) = @_;
  Moonpig->env->storage->do_with_ledger($guid, sub {

    my ($resource) = Moonpig->env->route(
      [ 'ledger', 'by-guid', $guid, 'invoice-history-events' ],
    );

    my $items = $resource->resource_request(get => {})->{items};
    return $items;

  });
}
