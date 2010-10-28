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

for my $thing (qw(receipt invoice)) {
  my $role   = sprintf "Moonpig::Role::%s", ucfirst $thing;
  my $class  = sprintf "Moonpig::%s::Basic", ucfirst $thing;
  my $plural = "${thing}s";
  my $reader = "_$plural";

  has $plural => (
    reader  => $reader,
    isa     => ArrayRef[ role_type($role) ],
    default => sub { [] },
    traits  => [ qw(Array) ],
    handles => {
      "_push_$thing" => 'push',
    },
  );

  my $_ensure_one_thing = sub {
    my ($self) = @_;

    my $things = $self->$reader;
    return if @$things and $things->[-1]->is_open;

    Class::MOP::load_class($class);
    require Moonpig::CostTree::Basic;

    my $thing = $class->new({
      cost_tree => Moonpig::CostTree::Basic->new(),
    });

    push @$things, $thing;
    return;
  };

  has "current_$thing" => (
    is   => 'ro',
    does => role_type($role),
    lazy => 1,
    default => sub {
      my ($self) = @_;
      $self->$_ensure_one_thing;
      $self->$reader->[-1];
    }
  );
}

1;
