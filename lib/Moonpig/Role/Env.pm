package Moonpig::Role::Env;
# ABSTRACT: an environment of globally-available behavior for all of Moonpig
use Moose::Role;

use Moonpig;

with(
  'Moonpig::Role::HandlesEvents',
  'Moonpig::Role::StubBuild',
  'Stick::Role::Routable::AutoInstance',
  'Stick::Role::Routable::ClassAndInstance',
);

use Moonpig::Consumer::TemplateRegistry;
use Moonpig::Events::Handler::Method;
use Moonpig::Ledger::PostTarget;
use Moonpig::MKits;
use Moonpig::Util qw(class);

use Moose::Util::TypeConstraints;

use Stick::Publisher 0.308;
use Stick::Publisher::Publish;
use Stick::WrappedMethod 0.303;  # allow non-Moose::Meta::Method methods

use namespace::autoclean;

has _global_share_from_env => (
  isa => 'ArrayRef',
  lazy => 1,
  traits => [ 'Array' ],
  handles  => { _global_share_from_env => 'elements' },
  init_arg => undef,
  default  => sub {
    return [ ] unless defined $ENV{MOONPIG_SHARE_DIRS};
    return [ split /:/, $ENV{MOONPIG_SHARE_DIRS} ];
  },
);

requires 'extra_share_roots';

sub share_roots {
  my ($self) = @_;
  my @roots = $self->extra_share_roots;
  return (
    $self->_global_share_from_env,
    @roots,
    File::ShareDir::dist_dir('Moonpig'),
  );
};

requires 'default_from_email_address';
has from_email_address => (
  isa => class_type('Email::Address'),
  lazy     => 1,
  required => 1,
  init_arg => undef,
  builder  => 'default_from_email_address',
  handles  => {
    from_email_address_mailbox => 'address',
    from_email_address_phrase  => 'phrase',
    from_email_address_string  => 'format',
  }
);

has mkits => (
  is  => 'ro',
  isa => class_type('Moonpig::MKits'),
  init_arg => undef,
  default  => sub { Moonpig::MKits->new },
);

requires 'register_object';
requires 'now';

sub format_guid { return $_[1] }

has storage => (
  is   => 'ro',
  does => 'Moonpig::Role::Storage',
  lazy => 1,
  init_arg => undef,
  default  => sub {
    return $_[0]->storage_class->new(
      $_[0]->storage_init_args,
    );
  },
  clearer  => 'clear_storage',
  handles  => [ qw(save_ledger) ],
);

requires 'storage_class';
requires 'storage_init_args';

requires 'file_customer_service_request';
requires 'report_exception';

has consumer_template_registry => (
  is  => 'ro',
  isa => 'Moonpig::Consumer::TemplateRegistry',
  init_arg => undef,
  default  => sub { Moonpig::Consumer::TemplateRegistry->new },
  handles  => {
    consumer_template => 'template',
  },
);

sub _class_subroute {
  Moonpig::X->throw("cannot route through Moonpig environment class");
}

publish nothing => { -http_method => 'get' } => sub { return undef };

sub _extra_instance_subroute {
  my ($self, $path) = @_;

  if ($path->[0] eq 'ledger') {
    shift @$path;
    return scalar class('Ledger');
  }

  if ($path->[0] eq 'ledgers') {
    shift @$path;
    return 'Moonpig::Ledger::PostTarget';
  }

  if ($path->[0] eq 'consumer-template') {
    shift @$path;
    my $name = shift @$path;
    return Stick::WrappedMethod->new({
      invocant   => $self,
      get_method => sub { $self->consumer_template($name); },
    });
  }

  return;
}

my %MP_ENV;
sub import {
  my ($class) = @_;
  my $THIS = $MP_ENV{ $class } ||= $class->new;
  Moonpig->set_env($THIS)
};

sub STORABLE_freeze {
  confess "attempted to Storable::freeze the environment";
}

1;
