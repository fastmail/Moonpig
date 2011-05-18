package Fauxbox::Schema::Result::Account;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('accounts');

__PACKAGE__->add_columns(id => {
  data_type         => 'INTEGER',
  is_auto_increment => 1,
});

__PACKAGE__->add_columns(client_id => {
  data_type         => 'INTEGER',
});

__PACKAGE__->add_columns(premium_since => {
  data_type         => 'INTEGER',
  is_nullable       => 1,
});

sub is_premium {
  my ($self) = @_;
  return defined $self->premium_since;
}

sub was_premium_at {
  my ($self, $datetime) = @_;

  return unless $self->is_premium;
  my $epoch = $datetime->epoch;
  return $epoch >= $self->premium_since;
}

__PACKAGE__->add_columns(qw( alias fwd ));

__PACKAGE__->set_primary_key('id');

__PACKAGE__->belongs_to(
  client => 'Fauxbox::Schema::Result::Client',
  { 'foreign.id' => 'self.client_id' },
);

__PACKAGE__->has_many(
  active_flag => 'Fauxbox::Schema::Result::AccountActiveFlag',
  {
    'foreign.id'    => 'self.id',
    'foreign.alias' => 'self.alias',
  },
);

1;
