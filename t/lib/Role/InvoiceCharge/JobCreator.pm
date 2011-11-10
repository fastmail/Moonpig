package t::lib::Role::InvoiceCharge::JobCreator;
use Moose::Role;

use Moonpig::Behavior::EventHandlers;

implicit_event_handlers {
  return {
    'paid' => {
      'create-job' => Moonpig::Events::Handler::Method->new('create_job'),
    },
  },
};

sub create_job {
  my ($self, $event) = @_;

  $self->ledger->queue_job('job.on.payment' => {
    consumer_guid => $self->owner_guid,
    created_by    => __PACKAGE__,
  });
}

1;
