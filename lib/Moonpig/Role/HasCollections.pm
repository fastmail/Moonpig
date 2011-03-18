package Moonpig::Role::HasCollections;
use Moonpig::Util qw(class);
use Moonpig::Types qw(Factory);
use MooseX::Role::Parameterized;
use MooseX::Types::Moose qw(Str HashRef Defined);

=head2 USAGE

	package Fruitbasket;
	with (Moonpig::Role::HasCollections => {
	  item => 'banana',
          item_factory => 'Fruit::Banana',
        });

        sub banana_array { ... }   # Should return an array of this object's
                                   # bananas

        sub add_banana { ... }     # Should add a banana to this object

        package main;
        my $basket = Fruitbasket->new(...);

        my $bananas = $basket->banana_collection({...});
        $bananas->items;     # same as $basket->banana_array
        $bananas->_all       # same as @{$basket->banana_array}
        $bananas->_count;    # number of bananas
        $bananas->_pages;    # return number of pages of bananas
        $bananas->_page(3);  # return list of bananas on page 3
	$bananas->_add($platano) # Add the platano to the fruitbasket

        # Stick published methods
        find_by_guid($guid)
        find_by_xid($xid)
        all                 # like ->_all
        count               # like ->_count
        pages               # like ->_pages
        page(3)             # like ->_page(3)

=cut

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
  isa => Factory,
  lazy => 1,
  default => sub {
    my ($p) = @_;
    require Moonpig::Role::CollectionType;
    my $item_factory = $p->item_factory;
    my $item_class = ref($item_factory) || $item_factory;
    my $item_collection_role = Moonpig::Role::CollectionType->meta->
      generate_role(parameters => {
        item_class => $item_class,
        add_this_item => $p->add_this_thing,
      });
    my $c = class({ $p->item_collection_name => $item_collection_role});
    return $c;
  },
);

# Name for the item collection class
# e.g., "RefundCollection";
parameter item_collection_name => (
  isa => Str, lazy => 1,
  default => sub {
    my ($p) = @_;
    ucfirst($p->item . "Collection");
  },);

sub methods {
  my ($x) = @_;
  my $class = ref($x) || $x;
  no strict 'refs';
  my $stash = \%{"$class\::"};
  for my $k (sort keys %$stash) {
    print STDERR "# $k (via $class)\n" if defined &{"$class\::$k"};
  }
  for my $parent (@{"$class\::ISA"}) {
    methods($parent);
  }
}

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
parameter add_this_thing => (isa => Str, lazy => 1,
                             default => sub { "add_this_" . $_[0]->item },
                            );

role {
  my ($p) = @_;
  my $thing = $p->item;
  my $things = $p->items;
  my $accessor = $p->accessor || "$thing\_array";
  my $constructor = $p->constructor || "$thing\_collection";
  my $add_this_thing = $p->add_this_thing || "add_this_$thing";
  my $collection_factory = $p->factory;

  # the accessor method is required
  requires $accessor;
  requires $add_this_thing;

  # build collection constructor
  method $constructor => sub {
    my ($parent, $opts) = @_;
    $p->factory->new({
      items => $parent->$accessor,
      options => $opts,
      ledger => $parent->ledger
    });
  };
};

1;
