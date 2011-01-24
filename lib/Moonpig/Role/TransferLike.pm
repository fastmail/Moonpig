package Moonpig::Role::TransferLike;
# ABSTRACT: something that transfers money from one thing to another
use MooseX::Role::Parameterized;

use Moonpig;
use Moonpig::Types qw(Millicents Time);
use MooseX::Types::Perl qw(Identifier);

use namespace::autoclean;

parameter from_name => (isa => Identifier, required => 1);
parameter to_name   => (isa => Identifier, required => 1);

parameter from_type => (isa => 'Moose::Meta::TypeConstraint', required => 1);
parameter to_type   => (isa => 'Moose::Meta::TypeConstraint', required => 1);

parameter allow_deletion => (isa => 'Bool', default => 0);

my %MASTER_FROM;
my %MASTER_TO;

role {
  my ($p) = @_;

  my $FROM = $p->from_name;
  my $TO   = $p->to_name;

  my $BY_FROM = $MASTER_FROM{$FROM} ||= {};
  my $BY_TO   = $MASTER_TO{$TO}     ||= {};

  with ('Moonpig::Role::HasGuid');

  # We will need this method for deleting holds, for example.
  # -- rjbs, 2010-12-02
  method "__$FROM\_$TO\_storage" => sub {
    return ($BY_FROM, $BY_TO);
  };

  method delete => sub {
    my ($self) = @_;
    Carp::croak("cannot delete immortal object $self") if ! $p->allow_deletion;

    for my $store ($BY_FROM->{ $self->$FROM->guid },
                   $BY_TO->{ $self->$TO->guid }) {
      @$store = grep { $_->guid ne $self->guid } @$store;
    }
  };

  has $FROM => (
    is   => 'ro',
    isa  => $p->from_type,
    required => 1,
  );

  has $TO => (
    is   => 'ro',
    isa  => $p->to_type,
    required => 1,
  );

  my $by_from = "all_for_$FROM";
  method $by_from => sub {
    my ($class, $from_item) = @_;

    my $from_id = $from_item->guid;
    my $ref = $BY_FROM->{ $from_id } || [];
    return [ @$ref ];
  };

  my $by_to = "all_for_$TO";
  method $by_to => sub {
    my ($class, $to_item) = @_;

    my $to_id = $to_item->guid;
    my $ref = $BY_TO->{ $to_id } || [];
    return [ @$ref ];
  };

  has amount => (
    is  => 'ro',
    isa =>  Millicents,
    coerce   => 1,
    required => 1,
  );

  has date => (
    is => 'ro',
    isa => Time,
    default => sub { Moonpig->env->now() },
  );

  my $assert_no_overtransfer = sub {
    my ($self) = @_;

    confess "refusing to perform overtransfer"
      if $self->amount > $self->$FROM->unapplied_amount;
  };

  method BUILD => sub {
    my ($self) = @_;

    $self->$assert_no_overtransfer;

    my $from_id = $self->$FROM->guid;
    $BY_FROM->{ $from_id } ||= [];
    push @{ $BY_FROM->{ $from_id } }, $self;

    my $to_id = $self->$TO->guid;
    $BY_TO->{ $to_id } ||= [];
    push @{ $BY_TO->{ $to_id } }, $self;
  };
};


1;
