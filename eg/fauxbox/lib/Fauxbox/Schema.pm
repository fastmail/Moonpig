package Fauxbox::Schema;
use base qw/DBIx::Class::Schema/;

use File::Spec;

__PACKAGE__->load_namespaces();

my $conn;
sub shared_connection {
  my ($self) = @_;

  my $root = $ENV{FAUXBOX_STORAGE_ROOT};
  my $file = File::Spec->catfile($root, 'fauxbox.sqlite');

  return $conn ||= $self->connect("dbi:SQLite:dbname=$file");
}

1;
