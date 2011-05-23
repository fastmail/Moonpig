package Moonpig::Types;
# ABSTRACT: type constraints for use with Moonpig
use MooseX::Types -declare => [ qw(
  EmailAddresses
  Ledger Consumer
  Millicents PositiveMillicents
  Credit

  Invoice

  Event
  EventName EventHandlerName EventHandler
  EventHandlerMap

  ChargePath ChargePathPart ChargePathStr

  GUID MRI XID

  Tag TagSet

  Time TimeInterval

  TransferCapable TransferType

  PositiveInt

  Factory
) ];

use MooseX::Types::Moose qw(ArrayRef HashRef Int Num Str Object);
# use MooseX::Types::Structured qw(Map);
use Data::GUID 0.046 ();
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

role_type Consumer, { role => 'Moonpig::Role::Consumer' };

role_type Invoice, { role => 'Moonpig::Role::Invoice' };

subtype PositiveInt, as Int, where { $_ > 0 };

subtype Millicents, as Int;
subtype PositiveMillicents, as Millicents, where { $_ > 0 };

coerce Millicents, from Num, via { int };
coerce PositiveMillicents, from Num, via { int };

role_type Credit, { role => 'Moonpig::Role::Credit' };

subtype Factory, as Str | Object;

################################################################
#
# Events

my $simple_str            = qr/[-a-z0-9]+/i;
my $simple_str_dotchain   = qr/ (?: $simple_str \. )* $simple_str ? /x;
my $simple_str_colonchain = qr/ (?: $simple_str \: )* $simple_str ? /x;

my $colon_dot_chain = qr/
  (?: $simple_str_colonchain \. )*
  $simple_str_colonchain ?
/x;

class_type Event, { class => 'Moonpig::Events::Event' };

subtype EventName,        as Str, where { /\A$simple_str_dotchain\z/ };
subtype EventHandlerName, as Str, where { /\A$simple_str_dotchain\z/ };

role_type EventHandler, { role => 'Moonpig::Role::EventHandler' };

subtype EventHandlerMap, as HashRef[ HashRef[ EventHandler ] ];

################################################################
#
# ChargePath

subtype ChargePathPart, as Str, where { /\A$simple_str_colonchain\z/ };
subtype ChargePath, as ArrayRef[ ChargePathPart ];

subtype ChargePathStr, as Str, where { /\A$colon_dot_chain\z/ };

coerce ChargePath, from ChargePathStr, via { [ split /\./, $_ ] };

################################################################
#
# Tags

# XXX: TagSet should be an actual Set, but MooseX::Types::Set::Object is a pain
# and I don't feel like fixing it right this second. -- rjbs, 2011-05-23
subtype Tag, as Str, where { /\A $simple_str \z/x };
subtype TagSet, as ArrayRef[ Tag ];

################################################################
#
# GUID

subtype GUID, as Str, where { $_ =~ Data::GUID->string_guid_regex };

subtype XID, as Str, where { /\A$simple_str_colonchain\z/ };

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

################################################################
#
# Transfer types

use Moonpig::TransferUtil qw(is_transfer_capable valid_type);

subtype TransferCapable, as Str, where { is_transfer_capable($_) };
subtype TransferType, as Str, where { valid_type($_) };
1;
