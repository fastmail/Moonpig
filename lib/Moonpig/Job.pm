package Moonpig::Job;
use Moose;
# ABSTRACT: a job to be carried out by a worker

use MooseX::StrictConstructor;
require Stick::Role::HasCollection;
Stick::Role::HasCollection->VERSION(0.20110802);

use Stick::Publisher 0.20110324;
use Stick::Publisher::Publish 0.20110324;
use Moose::Util::TypeConstraints qw(enum);

use namespace::autoclean;

my @callbacks = qw(
  log
  get_logs
  mark_complete
  cancel
);

for my $cb (@callbacks) {
  has "$cb\_callback" => (
    is  => 'ro',
    isa => 'CodeRef',
    required => 1,
    traits   => [ 'Code' ],
    handles  => { $cb => 'execute_method' },
  );
}

with(
  'Stick::Role::Routable::AutoInstance',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::HasCollection' => {
    is   => 'ro',
    item => 'log',
    item_roles => [ ],
    accessor   => 'get_logs',
   },
);

sub _class_subroute { ... }

sub _extra_instance_subroute {
  my ($self, $path, $npr) = @_;
  my ($first) = @$path;
  my %x_rt = (
    logs  => $self->log_collection,
  );
  if (exists $x_rt{$first}) {
    shift @$path;
    return $x_rt{$first};
  }
  return;
}

use Moonpig::Types qw(GUID SimplePath Time);

use Moonpig::Behavior::Packable;

use namespace::autoclean;

has job_id => (
  is  => 'ro',
  isa => 'Int',
  required => 1,
);

has created_at => (
  is  => 'ro',
  isa => Time,
  coerce   => 1,
  required => 1,
);

has job_type => (
  is  => 'ro',
  isa => SimplePath,
  required => 1,
);

has ledger_guid => (
  is  => 'ro',
  isa => GUID,
  required => 1,
);

has payloads => (
  is  => 'ro',
  isa => 'HashRef',
  traits   => [ 'Hash' ],
  required => 1,
  handles  => {
    payload => 'get',
  },
);

has status => (
  is  => 'ro',
  isa => enum([ qw(incomplete done canceled) ]),
  writer   => '_set_status',
  required => 1,
);

after cancel        => sub { $_[0]->_set_status('canceled') };
after mark_complete => sub { $_[0]->_set_status('done') };

sub guid { $_[0]->job_id }

PARTIAL_PACK {
  my ($self) = @_;
  return {
    id   => $self->job_id,
    type => $self->job_type,
    created_at  => $self->created_at,
    payloads    => $self->payloads,
    ledger_guid => $self->ledger_guid,
    status      => $self->status,
  };
};

publish handle_cancel => { -http_method => 'post', -path => 'cancel' } => sub {
  my ($self) = @_;
  $self->cancel;
  return;
};

1;
