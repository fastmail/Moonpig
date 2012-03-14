package t::lib::Role::Refundable::Test;
use Moose::Role;

with(
  'Moonpig::Role::Credit::Refundable::ViaCustSrv',
);

1;
