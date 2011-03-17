package Moonpig::Role::CollectionType;
use Moose::Util::TypeConstraints qw(class_type);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(ArrayRef Defined HashRef Maybe Str);
use Moonpig::Types qw(PositiveInt);
use POSIX qw(ceil);
use Carp 'confess';

parameter item_class => (
  is => 'ro',
  isa => Str,
  required => 1,
);

# name of the ledger method that adds a new item of this type to a ledger
parameter add_item => (
  is => 'ro',
  isa => Str,
  required => 1,
);

role {
  require Stick::Publisher;
  Stick::Publisher->import();
  sub publish;

  my ($p) = @_;
  my $add_item = $p->add_item;
  with (qw(Moonpig::Role::LedgerComponent));

  has items => (
    is => 'ro',
    isa => ArrayRef [class_type($p->item_class)],
    default => sub { [] },
    traits => [ 'Array' ],
    handles => {
      n_items => 'count',
      item_list => 'elements',
      _push => 'push',
    },
   );

  publish all => { } => sub {
    my ($self) = @_;
    return $self->item_list;
  };

  publish count => { } => sub {
    my ($self) = @_;
    return $self->n_items;
  };

  # Page numbers start at 1.
  publish page => { pagesize => Maybe[PositiveInt],
                    page => PositiveInt,
                  } =>
    sub {
      my ($self, $ctx, $arg) = @_;
      my $pagesize = $arg->{pagesize} || $self->default_page_size();
      my $page = $arg->{page};
      my $start = $page * $pagesize;
      return @{$self->items}[$start .. $start+$pagesize-1];
    };

  # If there are 3 pages, they are numbered 1, 2, 3.
  publish pages => { pagesize => Maybe[PositiveInt],
                   } =>
    sub {
      my ($self, $ctx, $arg) = @_;
      my $pagesize = $arg->{pagesize} || $self->default_page_size();
      return ceil($self->n_items / $pagesize);
    };

  publish find_by_guid => { guid => Str } => sub {
    my ($self, $ctx, $arg) = @_;
    my $guid = $arg->{guid};
    my ($item) = grep { $_->guid eq $guid } $self->items;
    return $item;
  };

  publish find_by_xid => { xid => Str } => sub {
    my ($self, $ctx, $arg) = @_;
    my $xid = $arg->{xid};
    my ($item) = grep { $_->xid eq $xid } $self->items;
    return $item;
  };

  publish add => { new_item => Defined } => sub {
    my ($self, $ctx, $arg) = @_;
    $self->ledger->$add_item($arg->{new_item});
    $self->_push($arg->{new_item});
  };

  sub default_page_size { 20 }

};

1;
