package Moonpig::Role::Collection::CreditExtras;
use Moose::Role;
# ABSTRACT: extra behavior for a ledger's Credit collection

use Moonpig::Util qw(class event);
use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110504;

my %OK_ADD_ARG = map {; $_ => 1 } qw(
  type
  attributes
  quote_guid
  send_receipt
);

sub add {
  my ($self, $arg) = @_;
  my $type = $arg->{type};

  my $ledger = $self->owner;

  my @unknown = grep { ! $OK_ADD_ARG{ $_ } } keys %$arg;
  Moonpig::X->throw("unknown arguments: @unknown") if @unknown;

  return Moonpig->env->storage->do_rw(sub {
    if ($arg->{quote_guid}) {
      my $quote = $ledger->invoice_collection->find_by_guid({
        guid => $arg->{quote_guid},
      });
      $quote->execute;
    }

    my $credit = $ledger->add_credit(
      class("Credit::$type"),
      $arg->{attributes},
    );

    # XXX: I have a hard time believing these saves are really useful.
    # -- rjbs, 2012-09-13
    $ledger->save;
    $ledger->process_credits;
    $ledger->save;

    if ($arg->{send_receipt}) {
      $ledger->handle_event(event('send-mkit', {
        kit => 'receipt',
        arg => {
          subject => "Payment received",

          to_addresses => [ $ledger->contact->email_addresses ],
          credit       => $credit,
          ledger       => $ledger,
        },
      }));
    }

    return $credit;
  });
};

1;

