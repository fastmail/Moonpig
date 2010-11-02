
package main::test;
use strict;
use warnings;

use Carp qw(confess croak);
use DateTime;
use Moonpig::Types qw(MRI);
use Moonpig::URI;
use overload;
use Test::More;
use Test::Routine::Util;
use Test::Routine;
use Try::Tiny;

has mri => (
  is => 'rw',
  isa => MRI,
  coerce => 1,
);

test "good coercions" => sub {
  my ($self) = @_;
  plan tests => 3 * 2;
  for my $good ("moonpig:/consumer/id/123456",
                Moonpig::URI->nothing(),
                URI->new("moonpig:/consumer/id/123456"),
               ) {
    try {
      $self->mri($good);
    } finally {
      if (@_) {
        fail("died: $@");
        fail();
      } else {
        ok($self->mri);
        isa_ok($self->mri, "Moonpig::URI");
      }
    }
  }
};

test "bad coercions" => sub {
  my ($self) = @_;
  plan tests => 3;

  for my $bad ("http://blog.plover.com/",
               URI->new("http://blog.plover.com/"),
               DateTime->now,
              ) {
    try {
      $self->mri($bad);
    } finally {
      ok(@_, "inappropriate coercion");
    }
  }
};

#my $mri = Moonpig::URI->new("http://blog.plover.com/");
#      note "mri = $mri";
#exit;

run_me;
done_testing;


