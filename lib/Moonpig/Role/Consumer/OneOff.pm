package Moonpig::Role::Consumer::OneOff;
# ABSTRACT: a consumer that issues one-off charges that end up in general funds

use Carp qw(confess croak);
use List::AllUtils qw(all any);
use Moonpig;
use Moonpig::DateTime;
use Moonpig::Util qw(class days event sum sumof);
use Moose::Role;
use MooseX::Types::Moose qw(ArrayRef Num);

use Moonpig::Logger '$Logger';
use Moonpig::Trait::Copy;
use POSIX qw(ceil);

require Stick::Publisher;
Stick::Publisher->VERSION(0.20110324);
use Stick::Publisher::Publish 0.20110324;

with(
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
);

use Moonpig::Types qw(PositiveMillicents Time TimeInterval TrimmedNonBlankLine);

use namespace::autoclean;

has consumes_funds => (
  is  => 'ro',
  isa => 'Bool',
  default => 0,
);

# This consumer never charges unless specifically told to. -- rjbs, 2016-03-16
around maybe_charge => sub { };
sub charge { ... }

publish oneoff_issue_charge => {
  -path => 'oneoff-issue-charge',
  -http_method => 'post',
  amount      => PositiveMillicents,
  description => TrimmedNonBlankLine,
} => sub {
  my ($self, $arg) = @_;

  my $charge = $self->charge_current_invoice({
    description => $arg->{description},
    amount      => $arg->{amount},
  });

  return $charge;
};

sub build_invoice_charge {
  my ($self, $args) = @_;
  class("InvoiceCharge::OneOff")->new($args);
}

{
  package Moonpig::Role::InvoiceCharge::OneOff;
  BEGIN { $INC{'Moonpig/Role/InvoiceCharge/OneOff.pm'} = 1 } # perl :-/

  use Moose::Role;
  with qw(Moonpig::Role::InvoiceCharge);

  use namespace::autoclean;

  around acquire_funds => sub {
    my ($orig, $self, @arg) = @_;

    my $owner = $self->owner;

    if ($owner->consumes_funds) {
      $self->$orig(@arg);
      $owner->charge_current_journal({
        amount      => $self->amount,
        description => $self->description,
      });
    } else {
      $self->__set_executed_at( Moonpig->env->now );
    }

    $self->owner->expire;
  };
}

1;
