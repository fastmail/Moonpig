use strict;
use warnings;
use Test::More;

use Moonpig::Util -all;

note q{   a    b              };
note q{ 0 -> 1 -> 2           };
note q{      \ c              };
note q{       `-> 3 -> 4 -> 5 };
note q{             d    f    };

my @ct;
$ct[0] = class('ChargeTree')->new;
$ct[1] = $ct[0]->path_search('a', { create => 1 });
$ct[2] = $ct[0]->path_search('a.b', { create => 1 });
$ct[3] = $ct[0]->path_search('a.c', { create => 1 });
$ct[4] = $ct[0]->path_search('a.c.d', { create => 1 });
$ct[5] = $ct[0]->path_search('a.c.d.f', { create => 1 });

my %lookup = map {; "$ct[$_]" => $_ } (0 .. 5);

is($ct[0]->_parent, undef, "tree 0: no parent");

ok(same_object($ct[1]->_parent, $ct[0]), "tree 1: parent is tree 0");
ok(same_object($ct[2]->_parent, $ct[1]), "tree 2: parent is tree 1");
ok(same_object($ct[3]->_parent, $ct[1]), "tree 3: parent is tree 1");
ok(same_object($ct[4]->_parent, $ct[3]), "tree 4: parent is tree 3");
ok(same_object($ct[5]->_parent, $ct[4]), "tree 5: parent is tree 4");

my @children = (
  [ 1 ],
  [ 2, 3 ],
  [ ],
  [ 4 ],
  [ 5 ],
  [ ],
);

for (0 .. 5) {
  my @child_indexes = sort map {; $lookup{ $_ } } $ct[$_]->subtrees;
  is_deeply( \@child_indexes, $children[ $_ ], "correct children of tree $_");
}

my $dump;
$dump = sub {
  my ($tree, $indent, $string_ref) = @_;

  $indent ||= 0;
  $string_ref ||= do { my $str = ''; \$str; };

  $$string_ref .= sprintf "%s%s\n", (q{ } x $indent), q{.} . $tree->_leaf_name;
  $dump->($_, $indent + 2, $string_ref)
    for map {; $tree->subtree_for($_) } sort $tree->subtree_names;

  return $$string_ref;
};

my $have = $dump->($ct[0], 0);
my $want = <<'END_TREE';
.
  .a
    .a.b
    .a.c
      .a.c.d
        .a.c.d.f
END_TREE

is($have, $want, "our dumper (_leaf_name test) works");

for (0 .. $#ct) {
  cmp_ok($ct[$_]->root, '==', $ct[0], "root of tree $_ is tree 0");
}

# Good paths
for my $test ([ [], 0 ],
              [ ["a"], 1 ],
              [ ["a", "b"], 2],
              [ ["a", "c"], 3],
              [ ["a", "c", "d"], 4],
              [ ["a", "c", "d", "f"], 5],
             ) {
  my ($path, $expected) = @$test;
  my $p = join ".", @$path;

  ok(
    same_object($ct[0]->path_search($path), $ct[$expected]),
    "0 -> $p -> $expected"
  );
}

my @old = @ct;
# Bad paths
for my $path (["b"], ["a", "a"], ["a", "d"], ["a", "x", "y", "z"]) {
  my $p = join ".", @$path;
  is($ct[0]->path_search($path), undef(), "0 -> $p -> nowhere");
  my $new = $ct[0]->path_search($path, { create => 1 });
  ok($new, "created $p");
  $new == $_ and die for @old;  # WHAAAA?
  is($ct[0]->path_search($path), $new, "0 -> $p -> new");
  push @old, $new;

  my @parent_path = @$path;
  pop @parent_path;
  is($new->_parent, $ct[0]->path_search(\@parent_path), "parent(new) ok");
}



done_testing;
