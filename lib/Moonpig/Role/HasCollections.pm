package Moonpig::Role::HasCollections;
use Moonpig::Util qw(class);
use Moonpig::Types qw(Factory);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(Str HashRef Defined);

requires 'ledger';

# Name of the sort of thing this collection will contain
# e.g., "refund".
parameter item => (isa => Str, required => 1);
# Plural version of above
parameter items => (isa => Str, lazy => 1,
                    default => sub { $_[0]->item . 's' },
                   );

# Class name or factory object for an item in the collection
# e.g., class('Refund')
parameter item_factory => (
  isa => Str, required => 1,
);

# Class name or factory object for the collection itself.
# e.g., "Moonpig::Class::RefundCollection", which will do
#   Moonpig::Role::CollectionType
parameter factory => (
  isa => Factory, lazy => 1,
  default => sub {
    require Moonpig::Role::CollectionType;
    my ($p) = @_;
    my $item_factory = $p->item_factory;
    my $item_class = ref($item_factory) || $item_factory;
    my $item_collection_role = Moonpig::Role::CollectionType->meta->
      generate_role(parameters => { item_class => $item_class });
    my $c = class($item_collection_role, $p->item_collection_name);
    return $c;
  },
);

# Name for the item collection class
# e.g., "RefundCollection";
parameter item_collection_name => (
  isa => Str, lazy => 1,
  default => sub {
    my ($p) = @_;
    "Moonpig::Class::" . ucfirst($p->item . "Collection");
  },
);

# Name of ledger method that returns an arrayref of the things
# default "thing_array"
parameter accessor => (isa => Str, lazy => 1,
                       default => sub {
                         $_[0]->item . "_array" },
                      );

# Method name for collection object constructor
# Default: "thing_collection"
parameter constructor => (isa => Str, lazy => 1,
                          default => sub { $_[0]->item . "_collection" },
                         );

# Names of ledger methods
parameter add_thing => (isa => Str, lazy => 1,
                        default => sub { "add_" . $_[0]->item },
                       );

role {
  my ($p) = @_;
  my $thing = $p->item;
  my $things = $p->items;
  my $accessor = $p->accessor || "$thing\_array";
  my $constructor = $p->constructor || "$thing\_collection";
  my $add_thing = $p->add_thing || "add_$thing";

  # the accessor method is required
  requires $accessor;
  requires $add_thing;

  # build collection constructor
  method $constructor => sub {
    my ($parent, $opts) = @_;
    $p->factory->new({
      items => [ $parent->accessor ],
      options => $opts,
      ledger => $parent->ledger
    });
  };
};

1;
