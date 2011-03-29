package Fauxbox::Schema::Result::Account;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('accounts');
__PACKAGE__->add_columns(qw( id client_id alias fwd ));
__PACKAGE__->set_primary_key('id');

__PACKAGE__->might_have(
  active_flag => 'Fauxbox::Schema::Result::AccountActiveFlag',
  { 'foreign.id' => 'self.id' },
);

1;
