package Moonpig::Types;
use MooseX::Types -declare => [ qw(
  EmailAddresses
  Ledger
  Millicents
  Payment

  Event
  EventName EventHandlerName EventHandler
  EventHandlerMap

  CostPath CostPathPart CostPathStr

  MRI
) ];

use MooseX::Types::Moose qw(ArrayRef HashRef Int Num Str);
# use MooseX::Types::Structured qw(Map);
use Email::Address;
use Moonpig::URI;

use namespace::autoclean;

subtype EmailAddresses, as ArrayRef, where {
  @$_ > 0
  and
  @$_ == grep { /\@/ } @$_
};

role_type Ledger, { role => 'Moonpig::Role::Ledger' };

subtype Millicents, as Int;

coerce Millicents, from Num, via { int };

role_type Payment, { role => 'Moonpig::Role::Payment' };

my $simple_str       = qr/[-a-z0-9]+/i;
my $simple_str_chain = qr/ (?: $simple_str \. )* $simple_str ? /x;

class_type Event, { class => 'Moonpig::Events::Event' };

subtype EventName,        as Str, where { /\A$simple_str_chain\z/ };
subtype EventHandlerName, as Str, where { /\A$simple_str_chain\z/ };

role_type EventHandler, { role => 'Moonpig::Role::EventHandler' };

subtype EventHandlerMap, as HashRef[ HashRef[ EventHandler ] ];

subtype CostPathPart, as Str, where { /\A$simple_str\z/ };
subtype CostPath, as ArrayRef[ CostPathPart ];

subtype CostPathStr, as Str, where { /\A$simple_str_chain\z/ };

coerce CostPath, from CostPathStr, via { [ split /\./, $_ ] };

{
  my $str_type = subtype as Str, where { /\Amoonpig:/ };

  my $uri_type = subtype as (class_type '__URI_moonpig', +{ class => 'URI' }),
    where { $_->scheme eq "moonpig" };

  class_type MRI, { class => 'Moonpig::URI' };
  coerce MRI, from $str_type, via { Moonpig::URI->new($_) },
              from $uri_type, via { Moonpig::URI->new("$_") };
}

1;
