package Fauxbox::Schema::Result::AccountActiveFlag;
use base qw/DBIx::Class::Core/;

__PACKAGE__->table('account_active_flags');
__PACKAGE__->add_columns(qw( id ));
__PACKAGE__->set_primary_key('id');

__PACKAGE__->add_columns(qw( alias ));

__PACKAGE__->belongs_to(
  account => 'Fauxbox::Schema::Result::Account',
  {
    'foreign.id'    => 'self.id',
    'foreign.alias' => 'self.alias',
  },
);

__PACKAGE__->add_unique_constraint([ qw(alias) ]);

1;
