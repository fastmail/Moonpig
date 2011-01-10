use strict;
use warnings;
package Moonpig::DateTime;
# ABSTRACT: a DateTime object with different math

use base 'DateTime';
use Carp qw(confess croak);
use overload
  '+' => \&plus,
  '-' => \&minus,
  '<=>' => \&compare,
;
use Scalar::Util qw(blessed reftype);

# XXX: When I enable this, Moonpig::Env::Test dies.  WTH? -- rjbs, 2011-01-10
# use namespace::autoclean;

sub new {
  my ($base, @arg) = @_;
  my $class = ref($base) || $base;

  if (@arg == 1) { return $class->from_epoch( epoch => $arg[0] ) }

  bless $class->SUPER::new(@arg) => $class;
}

sub new_datetime {
  my ($class, $dt) = @_;
  bless $dt->clone => $class;
}

# $a is expected to be epoch seconds
sub plus {
  my ($self, $a) = @_;
  my $class = ref($self) || $self;
  my $a_sec = $class->_to_sec($a);
  return $class->from_epoch( epoch => $self->epoch + $a_sec );
}

sub minus {
  my ($a, $b, $rev) = @_;
  # if $b is a datetime, the result is an interval
  # but if $b is an interval, the result is another datetime
  if (blessed($b)) {
    croak "Can't subtract X from $a when X has no 'epoch' method"
      unless $b->can("epoch");
    my $res = ( $a->epoch - $b->epoch ) * ($rev ? -1 : 1);
    return $a->interval_factory($res);
  } else { # $b is a number
    croak "subtracting a date from a number is forbidden"
      if $rev;
    return $a + (-$b);
  }
}

sub interval_factory { return $_[1] }

sub _to_sec {
  my ($self, $a) = @_;
  if (ref($a)) {
    if (blessed($a)) {
      if ($a->can('as_seconds')) {
        return $a->as_seconds;
      } else {
        croak "Can't add $self to object with no 'as_seconds' method";
      }
    } else {
      croak "Can't add $self to unblessed " . reftype($a) . " reference";
    }
  } else {
    return $a;
  }
}

sub compare {
  my ($self, $d, $rev) = @_;
  $self->SUPER::compare($d) * ($rev ? -1 : 1);
}

sub precedes {
  my ($self, $d) = @_;
  return $self->compare($d) < 0;
}

sub follows {
  my ($self, $d) = @_;
  return $self->compare($d) > 0;
}

1;
