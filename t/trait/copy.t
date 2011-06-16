
use strict;
use Test::More tests => 3;
BEGIN { use_ok("t::lib::TCopy") }

my $obj = t::lib::TCopy->new;
for my $attr ($obj->meta->get_all_attributes) {
  my $name = $attr->name;
  is ($attr->does("Moose::Meta::Attribute::Custom::Trait::Copy") ? 'yes' : 'no',
      $obj->$name(),
      "attribute '$name'");
}

done_testing;
