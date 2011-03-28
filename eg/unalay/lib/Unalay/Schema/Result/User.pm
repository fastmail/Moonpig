package Unalay::Schema::Result::User;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('users');
__PACKAGE__->add_columns(qw( username ));
__PACKAGE__->set_primary_key('username');

1;
