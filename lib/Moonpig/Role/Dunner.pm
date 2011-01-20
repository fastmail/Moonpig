package Moonpig::Role::Dunner;
# ABSTRACT: something that performs dunning of invoices
use Moose::Role;

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class event);

use namespace::autoclean;

has last_request_for_payment => (
  does      => 'Moonpig::Role::RequestForPayment',
  init_arg  => undef, # must be set by the RFP sender -- rjbs, 2011-01-18
  reader    => 'last_request_for_payment',
  writer    => '_set_last_request_for_payment',
  predicate => 'has_last_request_for_payment',
);

sub dunning_frequency { 3 * 86400 }

sub perform_dunning {
  my ($self) = @_;

  my @invoices =
    sort { $b->created_at <=> $a->created_at
        || $b->guid       cmp $a->guid # incredibly unlikely, but let's plan
         }
    grep { $_->is_unpaid } $self->invoices;

  return unless @invoices;

  if ($self->has_last_request_for_payment) {
    my $rfp = $self->last_request_for_payment;

    if ($rfp->latest_invoice->guid eq $invoices[0]->guid) {
      my $ago = Moonpig->env->now - $rfp->sent_at;

      return unless $ago > $self->dunning_frequency;
    }
  }

  $self->_send_request_for_payment(\@invoices);
}

sub _send_request_for_payment {
  my ($self, $invoices) = @_;

  $_->close for grep { $_->is_open } @$invoices;

  $Logger->log([
    "sending invoices %s to contacts of %s",
    [ map {; $_->ident } @$invoices ],
    $self->ident,
  ]);

  my $rfp = class(qw(RequestForPayment))->new({
    invoices => $invoices,
  });

  $self->_set_last_request_for_payment($rfp);

  $self->handle_event(event('send-mkit', {
    kit => 'generic',
    arg => {
      subject => "PAYMENT IS DUE",
      body    => "YOU OWE US MONEY\n",

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],
    },
  }));
}

1;
