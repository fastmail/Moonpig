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

sub xid {
  my ($self) = @_;
  sprintf "fauxbox:account:%d", $self->id;
}

sub consumer_uri {
  my ($self, $extra) = @_;
  my $base = sprintf "%s/consumers/xid/%s%s%s",
    $self->client->ledger_uri, $self->xid;
  $base .= "/$extra" if defined $extra;
  return $base;
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
