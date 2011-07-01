package Moonpig::Job;
use Moose;
use MooseX::StrictConstructor;

use Moonpig::Types qw(Ledger SimplePath);

use namespace::autoclean;

has job_id => (
  is  => 'ro',
  isa => 'Int',
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

my %callback = (
  lock     => [ qw(lock extend_lock) ],
  unlock   => [ qw(unlock)           ],
  log      => [ qw(log)              ],
  get_logs => [ qw(get_logs)      ],
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

has payloads => (
  is  => 'ro',
  isa => 'HashRef',
  traits   => [ 'Hash' ],
  required => 1,
  handles  => {
    payload => 'get',
  },
);

1;
