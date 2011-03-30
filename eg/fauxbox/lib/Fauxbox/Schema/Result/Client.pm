package Fauxbox::Schema::Result::Client;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('clients');
__PACKAGE__->add_columns(qw( id username ));
__PACKAGE__->set_primary_key('id');

__PACKAGE__->add_unique_constraint([ qw(username) ]);

1;
