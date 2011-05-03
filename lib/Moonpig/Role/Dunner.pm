package Moonpig::Role::Dunner;
# ABSTRACT: something that performs dunning of invoices
use Moose::Role;

use Moonpig::Logger '$Logger';
use Moonpig::Util qw(class event);
use Moonpig::Types qw(TimeInterval);
use Moonpig::Util qw(days);

use namespace::autoclean;

has rfp_history => (
  is => 'ro',
  isa => 'ArrayRef',
  default => sub { [] },
  init_arg => undef,
  traits => [ 'Array' ],
  handles => {
    has_last_request_for_payment => 'count',
    last_request_for_payment => [ get => -1 ],
    last_rfp => [ get => -1 ],
  },
);

# We can't provide these in the rpf_history attribute declaration
# because they need to be in place before the the with HasCollections
# declaration below, and rfp_history is not constructed until role
# composition time. 20110503 mjd
sub rfp_array { shift()->rfp_history(@_) }
sub add_this_rfp {
  my ($self, $rfp) = @_;
  push @{$self->rfp_history}, $rfp;
}

with(
  'Moonpig::Role::HasCollections' => {
    item => 'rfp',
    item_roles => [ 'Moonpig::Role::RequestForPayment' ],
    default_sort_key => 'sent_at',
   },
);

has dunning_frequency => (
  is => 'rw',
  isa => TimeInterval,
  default => days(3),
);

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

  $self->add_this_rfp($rfp);

  $self->handle_event(event('send-mkit', {
    kit => 'request-for-payment',
    arg => {
      subject => "PAYMENT IS DUE",

      # This should get names with addresses, unlike the contact-humans
      # handler, which wants envelope recipients.
      to_addresses => [ $self->contact->email_addresses ],
      request      => $rfp,
    },
  }));
}

1;
