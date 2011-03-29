package Fauxbox::Schema::Result::Service;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('services');
__PACKAGE__->add_columns(qw( id username type ));
__PACKAGE__->set_primary_key('id');

# add fk to users.username

1;
