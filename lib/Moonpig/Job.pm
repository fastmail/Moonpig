package Moonpig::Job;
use Moose;
use MooseX::StrictConstructor;

use namespace::autoclean;

has job_id => (
  is  => 'ro',
  isa => 'Int',
  required => 1,
);

has lock_callback => (
  is  => 'ro',
  isa => 'CodeRef',
  required => 1,
  traits   => [ 'Code' ],
  handles  => {
    lock        => 'execute_method',
    extend_lock => 'execute_method',
  },
);

has done_callback => (
  is  => 'ro',
  isa => 'CodeRef',
  required => 1,
  traits   => [ 'Code' ],
  handles  => {
    mark_complete => 'execute_method',
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

1;
