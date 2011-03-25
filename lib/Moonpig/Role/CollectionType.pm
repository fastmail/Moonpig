package Moonpig::Role::CollectionType;
use List::Util qw(min);
use Moose::Util::TypeConstraints qw(class_type);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(ArrayRef Defined HashRef Maybe Str);
use Moonpig::Types qw(PositiveInt);
use POSIX qw(ceil);
use Carp 'confess';
require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

parameter item_class => (
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

role {
  my ($p, %args) = @_;
  Stick::Publisher->import({ into => $args{operating_on}->name });
  sub publish;

  my $add_this_item = $p->add_this_item;
  my $item_type = class_type($p->item_class);

  with (qw(Moonpig::Role::LedgerComponent));

  has items => (
    is => 'ro',
    isa => ArrayRef [ $item_type ],
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
      _count => 'count',
      _all => 'elements',
      _push => 'push',
    },
   );

  has default_page_size => (
    is => 'rw',
    isa => PositiveInt,
    default => $p->pagesize,
  );

  publish all => { } => sub {
    my ($self) = @_;
    return $self->_all;
  };

  publish count => { } => sub {
    my ($self) = @_;
    return $self->_count;
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
    return @{$self->items}[$start .. $end];
  };

  # If there are 3 pages, they are numbered 1, 2, 3.
  publish pages => { pagesize => Maybe[PositiveInt],
                   } => sub {
    my ($self, $args) = @_;
    my $pagesize = $args->{pagesize} || $self->default_page_size();
    return ceil($self->_count / $pagesize);
  };

  publish find_by_guid => { guid => Str } => sub {
    my ($self, $arg) = @_;
    my $guid = $arg->{guid};
    my ($item) = grep { $_->guid eq $guid } $self->_all;
    return $item;
  };

  publish find_by_xid => { xid => Str } => sub {
    my ($self, $arg) = @_;
    my $xid = $arg->{xid};
    my ($item) = grep { $_->xid eq $xid } $self->_all;
    return $item;
  };

  publish add => { new_item => $item_type } => sub {
    my ($self, $arg) = @_;
    $self->_push($self->ledger->$add_this_item($arg->{new_item}));
  };
};

1;
