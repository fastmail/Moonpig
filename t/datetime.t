use strict;
use warnings;
use Test::More;
use Test::Fatal;

use t::lib::TestEnv;
use Moonpig::DateTime;

sub jan {
  my ($day) = @_;
  Moonpig::DateTime->new( year => 2000, month => 1, day => $day );
}

subtest compare => sub {
  my ($self) = @_;
  plan tests => 10;
  my ($j1, $j2) = (jan(1), jan(2));
  cmp_ok($j1, '==', $j1);
  cmp_ok($j1, '!=', $j2);
  ok(! $j1->precedes($j1));
  ok(  $j1->precedes($j2));
  ok(! $j2->precedes($j1));
  ok(! $j2->precedes($j2));
  ok(! $j1->follows($j1));
  ok(! $j1->follows($j2));
  ok(  $j2->follows($j1));
  ok(! $j2->follows($j2));
};

my $now_pair  = Moonpig::DateTime->from_epoch(epoch => $^T);
my $now_epoch = Moonpig::DateTime->new($^T);

cmp_ok($now_pair, '==', $now_epoch, 'one-arg constructor for M::DateTime');

my $x = bless {} => 'Bogus';

like(
  exception { $now_epoch + $x },
  qr/no 'as_seconds' method/,
  '$dt + $x; $x needs ->as_seconds',
);

like(
  exception { $now_epoch - $x },
  qr/no 'epoch' method/,
  '$dt - $x; $x needs ->epoch',
);

my $today     = $now_epoch;
my $yesterday = Moonpig::DateTime->new($^T - 86400);
cmp_ok( ($today - 86400), '==', $yesterday, '$dt - $secs'),;

like(
  exception { 86400 - $yesterday },
  qr/forbidden/,
  '$secs - $dt; fatal!',
);

cmp_ok($today, '>', $yesterday, '$today > $yesterday');
cmp_ok($yesterday, '<', $today, '$yesterday < $today');

ok($yesterday->precedes($today), "yesterday precedes today");
ok( ! $yesterday->follows($today), "yesterday doesn't follow today");

ok($today->follows($yesterday), "today follows yesterday");
ok(! $today->precedes($yesterday), "today doesn't precede yesterday");

my $birthday = Moonpig::DateTime->new(
  year      => 1978,
  month     => 7,
  day       => 20,
  hour      => 5,
  minute    => 0,
  second    => 32,
  time_zone => "UTC",
);

my $iso = '1978-07-20 05:00:32';

is($birthday->iso, $iso, '->iso formatter works');

is($birthday->TO_JSON, $birthday->iso, "->TO_JSON is just ->iso");

done_testing;
