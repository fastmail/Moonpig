package Moonpig::Types;
# ABSTRACT: type constraints for use with Moonpig
use MooseX::Types -declare => [ qw(
  EmailAddresses
  Ledger
  Millicents
  Credit

  Event
  EventName EventHandlerName EventHandler
  EventHandlerMap

  ChargePath ChargePathPart ChargePathStr

  MRI

  Time TimeInterval
) ];

use MooseX::Types::Moose qw(ArrayRef HashRef Int Num Str);
# use MooseX::Types::Structured qw(Map);
use DateTime;
use DateTime::Duration;
use Email::Address;
use Moonpig::DateTime;
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

role_type Credit, { role => 'Moonpig::Role::Credit' };

################################################################
#
# Events

my $simple_str       = qr/[-a-z0-9]+/i;
my $simple_str_chain = qr/ (?: $simple_str \. )* $simple_str ? /x;

class_type Event, { class => 'Moonpig::Events::Event' };

subtype EventName,        as Str, where { /\A$simple_str_chain\z/ };
subtype EventHandlerName, as Str, where { /\A$simple_str_chain\z/ };

role_type EventHandler, { role => 'Moonpig::Role::EventHandler' };

subtype EventHandlerMap, as HashRef[ HashRef[ EventHandler ] ];

################################################################
#
# ChargePath

subtype ChargePathPart, as Str, where { /\A$simple_str\z/ };
subtype ChargePath, as ArrayRef[ ChargePathPart ];

subtype ChargePathStr, as Str, where { /\A$simple_str_chain\z/ };

coerce ChargePath, from ChargePathStr, via { [ split /\./, $_ ] };

################################################################
#
# MRI
{
  my $str_type = subtype as Str, where { /\Amoonpig:/ };

  my $uri_type = subtype as (class_type '__URI_moonpig', +{ class => 'URI' }),
    where { $_->scheme eq "moonpig" };

  class_type MRI, { class => 'Moonpig::URI' };
  coerce MRI, from $str_type, via { Moonpig::URI->new($_) },
              from $uri_type, via { Moonpig::URI->new("$_") };
}

################################################################
#
# Time

class_type Time, { class => 'Moonpig::DateTime' };
coerce Time, from Num, via { Moonpig::DateTime->new_epoch($_) };

# Total seconds
subtype TimeInterval, as Num;

{
  my $dt_type = class_type '__DateTime', +{ class => 'DateTime' };
  coerce Time, from $dt_type, via { Moonpig::DateTime->new_datetime($_) };
}
{
  my $zero = DateTime->from_epoch ( epoch => 0 );
  my $dt_type = class_type '__DateTime', +{ class => 'DateTime::Duration' };
  coerce TimeInterval, from $dt_type,
    via { $zero->add_duration($_)->epoch }
}

1;
