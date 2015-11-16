package Moonpig::Role::Autocharger;
# ABSTRACT: something used by ledgers to get funds as needed

use Moose::Role;

with(
  'Moonpig::Role::HasCreatedAt',
  'Moonpig::Role::LedgerComponent',
  'Moonpig::Role::StubBuild',
  'Stick::Role::PublicResource',
  'Stick::Role::PublicResource::GetSelf',
  'Stick::Role::Routable::ClassAndInstance',
  'Stick::Role::Routable::AutoInstance',
);

requires 'charge_into_credit';


1;
