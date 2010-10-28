package Moonpig::Role::Ledger;
use Moose::Role;
with(
  'Moonpig::Role::HasGuid',
  'Moonpig::Role::HandlesEvents',
);

use Moose::Util::TypeConstraints;
use MooseX::SetOnce;
use MooseX::Types::Moose qw(ArrayRef HashRef);

use namespace::autoclean;

# Should this be plural?  Or what?  Maybe it's a ContactManager subsystem...
# https://trac.pobox.com/wiki/Billing/DB says that there is *one* contact which
# has *one* address and *one* name but possibly many email addresses.
# -- rjbs, 2010-10-12
has contact => (
  is   => 'ro',
  does => 'Moonpig::Role::Contact',
  required => 1,
);

has banks => (
  reader  => '_banks',
  isa     => HashRef[ role_type('Moonpig::Role::Bank') ],
  default => sub { {} },
  traits  => [ qw(Hash) ],
  handles => {
    _has_bank => 'exists',
    _set_bank    => 'set',
  },
);

has consumers => (
  reader  => '_consumers',
  isa     => HashRef[ role_type('Moonpig::Role::Consumer') ],
  default => sub { {} },
  traits  => [ qw(Hash) ],
  handles => {
    _has_consumer => 'exists',
    _set_consumer    => 'set',
  },
);

for my $thing (qw(bank consumer)) {
  Sub::Install::install_sub({
    as   => "add_$thing",
    code => sub {
      my ($self, $value) = @_;

      my $predicate = "_has_$thing";
      confess sprintf "%s with guid %s already present", $thing, $value->guid
        if $self->$predicate($value->guid);

      if ($value->ledger->guid ne $self->guid) {
        confess(sprintf "can't add $thing for ledger %s to ledger %s",
          $value->ledger->guid,
          $self->guid
        );
      }

      my $setter = "_set_$thing";
      $self->$setter($value->guid, $value);
    },
  });
}

has receipts => (
  reader  => '_receipts',
  isa     => ArrayRef[ role_type('Moonpig::Role::Receipt') ],
  default => sub { [] },
  traits  => [ qw(Array) ],
  handles => {
    _push_receipt => 'push',
  },
);

sub _ensure_at_least_one_receipt {
  my ($self) = @_;

  my $receipts = $self->_receipts;
  return if @$receipts and $receipts->[-1]->is_open;

  require Moonpig::Receipt::Basic;
  require Moonpig::CostTree::Basic;
  my $receipt = Moonpig::Receipt::Basic->new({
    cost_tree => Moonpig::CostTree::Basic->new(),
  });

  push @$receipts, $receipt;
  return;
}

has current_receipt => (
  is   => 'ro',
  does => role_type('Moonpig::Role::Receipt'),
  lazy => 1,
  default => sub {
    my ($self) = @_;
    $self->_ensure_at_least_one_receipt;
    $self->_receipts->[-1];
  }
);

1;
