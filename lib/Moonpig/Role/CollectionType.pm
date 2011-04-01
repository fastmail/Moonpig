package Moonpig::Role::CollectionType;
use List::Util qw(min);
use Moose::Util::TypeConstraints qw(role_type);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(Any ArrayRef Defined HashRef Maybe Str);
use Moonpig::Types qw(PositiveInt);
use POSIX qw(ceil);
use Carp 'confess';
require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

# name of the ledger method that retrieves an array of items
parameter item_array => (
  is => 'ro',
  isa => Str,
  required => 1,
);

# name of the ledger method that adds a new item of this type to a ledger
parameter add_this_item => (
  is => 'ro',
  isa => Str,
  required => 1,
);

parameter pagesize => (
  is => 'rw',
  isa => PositiveInt,
  default => 20,
);

parameter item_roles => (
  isa => ArrayRef [ Str ],
  is => 'ro',
  required => 1,
);

sub item_type {
  my ($p) = @_;
  my @roles = map role_type($_), @{$p->item_roles};
  if (@roles == 0) { return Any }
  elsif (@roles == 1) { return $roles[0] }
  else {
    require Moose::Meta::TypeConstraint::Union;
    return Moose::Meta::TypeConstraint::Union
      ->new(type_constraints => \@roles);
  }
}

role {
  my ($p, %args) = @_;
  Stick::Publisher->import({ into => $args{operating_on}->name });
  sub publish;

  my $add_this_item = $p->add_this_item;
  my $item_array = $p->item_array;
  my $item_type = item_type($p);

  with (qw(Moonpig::Role::LedgerComponent));


  method items => sub {
    return $_[0]->ledger->$item_array;
  };

  has default_page_size => (
    is => 'rw',
    isa => PositiveInt,
    default => $p->pagesize,
  );

  publish all => { } => sub {
    my ($self) = @_;
    return @{$self->items};
  };

  publish count => { } => sub {
    my ($self) = @_;
    return scalar @{$self->items};
  };

  # Page numbers start at 1.
  publish page => { pagesize => Maybe[PositiveInt],
                    page => PositiveInt,
                  } => sub {
    my ($self, $args) = @_;
    my $pagesize = $args->{pagesize} || $self->default_page_size();
    my $pagenum = $args->{page};
    my $items = $self->items;
    my $start = ($pagenum-1) * $pagesize;
    my $end = min($start+$pagesize-1, $#$items);
    return [ @{$items}[$start .. $end] ];
  };

  # If there are 3 pages, they are numbered 1, 2, 3.
  publish pages => { pagesize => Maybe[PositiveInt],
                   } => sub {
    my ($self, $args) = @_;
    my $pagesize = $args->{pagesize} || $self->default_page_size();
    return ceil($self->count / $pagesize);
  };

  publish find_by_guid => { guid => Str } => sub {
    my ($self, $arg) = @_;
    my $guid = $arg->{guid};
    my ($item) = grep { $_->guid eq $guid } $self->all;
    return $item;
  };

  publish find_by_xid => { xid => Str } => sub {
    my ($self, $arg) = @_;
    my $xid = $arg->{xid};
    my ($item) = grep { $_->xid eq $xid } $self->all;
    return $item;
  };

  publish add => { new_item => $item_type } => sub {
    my ($self, $arg) = @_;
    $self->ledger->$add_this_item($arg->{new_item});
  };
};

1;
