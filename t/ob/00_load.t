
use Test::Routine;
use Test::Routine::Util -all;
use Test::More;

with ('t::lib::Role::UsesStorage');
BEGIN { use_ok('Moonpig::App::Ob') }

test "load and ->new module" => sub {
  my ($self) = @_;
  local $ENV{MOONPIG_STORAGE_ROOT} = $self->tempdir;

  my $ob = Moonpig::App::Ob->new();
  ok($ob);
};

run_me;
done_testing;
