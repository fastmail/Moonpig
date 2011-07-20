package Moonpig::Job;
use Moose;
use MooseX::StrictConstructor;

my %callback = (
  lock     => [ qw(lock extend_lock) ],
  unlock   => [ qw(unlock)           ],
  log      => [ qw(log)              ],
  get_logs => [ qw(get_logs)         ],
  done     => [ qw(mark_complete)    ],
);

for my $key (keys %callback) {
  has "$key\_callback" => (
    is  => 'ro',
    isa => 'CodeRef',
    required => 1,
    traits   => [ 'Code' ],
    handles  => {
      map {; $_ => 'execute_method' } ($key, @{ $callback{ $key } })
    },
  );
}

with(
  'Stick::Role::Routable::AutoInstance',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Moonpig::Role::HasCollection' => {
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

use Moonpig::Types qw(Ledger SimplePath Time);

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

has ledger => (
  is  => 'ro',
  isa => Ledger,
  required => 1,
  handles  => {
    ledger_guid => 'guid',
  },
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

sub guid { $_[0]->job_id }

PARTIAL_PACK {
  my ($self) = @_;
  return {
    id   => $self->job_id,
    type => $self->job_type,
    created_at  => $self->created_at,
    payloads    => $self->payloads,
    ledger_guid => $self->ledger->guid,
  };
};

1;
