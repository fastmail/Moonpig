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
parameter item_class => (
  isa => Str, required => 1,
);

# Class name or factory object for the collection itself.
# e.g., "Moonpig::Class::RefundCollection", which will do
#   Moonpig::Role::CollectionType
parameter factory => (
  isa => Factory, lazy => 1,
  default => sub {
    require 'Moonpig::Role::CollectionType';
    my ($p) = @_;
    my $item_factory = $p->item_factory;
    my $item_class = ref($item_factory) || $item_factory;
    my $item_collection_role = Moonpig::Role::CollectionType->meta->
      generate_role(parameters => { item_type => $p->item_class });
    class($item_collection_role, $p->item_collection_name);
  },
);

# Name for the item collection name
# e.g., "RefundCollection";
parameter item_collection_name => (
  isa => Str, lazy => 1,
  default => sub {
    my ($p) = @_;
    ucfirst($p->item . "Collection");
  },
);

# Name of ledger method that returns an arrayref of the things
# default "get_all_things"
parameter accessor => (isa => Str, lazy => 1,
                       default => sub { "get_all_" . $_[0]->items },
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
  my $accessor = $p->accessor || "get_all_$things";
  my $constructor = $p->constructor || "$thing\_collection";
  my $add_thing = $p->add_thing || "add_$thing";

  # the accessor method is required
  requires $accessor;
  requires $add_thing;

  # build collection constructor
  method $constructor => sub {
    my ($parent, $opts) = @_;
    $parent->factory->new(
      items => [ $parent->accessor ],
      options => $opts,
      ledger => $parent->ledger
    );
  };
};

1;
