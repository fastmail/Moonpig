package Moonpig::Role::ConsumerComponent;
# ABSTRACT: something that is owned by a consumer

use Moose::Role;
with ("Moonpig::Role::StubBuild");

use namespace::autoclean;
use Moonpig::Types qw(GUID);

# translate ->new({consumer => ... }) to
# ->new({ ledger_guid => ..., owner_guid => ... })
around BUILDARGS => sub {
  my $orig  = shift;
  my $class = shift;
  my $args = shift;

  if (my $consumer = delete $args->{consumer}) {
    $args->{owner_guid}  ||= $consumer->guid;
    $args->{ledger_guid} ||= $consumer->ledger->guid;
  }

  return $class->$orig($args, @_);
};

has owner_guid => (
  is   => 'ro',
#  does => 'Moonpig::Role::Consumer',
  isa => GUID,
  required => 1,
);

sub owner {
  my ($self) = @_;
  $self->ledger->consumer_collection
    ->find_by_guid({ guid => $self->owner_guid });
}

has ledger_guid => (
  is   => 'ro',
  isa => GUID,
  required => 1,
);

sub ledger {
  my ($self) = @_;
  my $ledger = Moonpig->env->storage->retrieve_ledger_for_guid(
    $self->ledger_guid
  );

  return($ledger || Moonpig::X->throw("couldn't find ledger for charge"));
}

1;

