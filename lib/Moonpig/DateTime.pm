package Moonpig::DateTime;

use base 'DateTime';
use Carp qw(confess croak);
use strict;
use warnings;
use overload
  '+' => \&plus,
  '-' => \&minus,
  '<=>' => \&compare,
;
use Scalar::Util qw(blessed reftype);

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
  my $a_sec = $self->_to_sec($a);
  return $self->from_epoch( epoch => $self->epoch + $a_sec );
}

sub minus {
  my ($a, $b, $rev) = @_;
  my $res = ( $a->epoch - $b->epoch ) * ($rev ? -1 : 1);
  return $a->interval_factory($res);
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
