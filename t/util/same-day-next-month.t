use strict;
use warnings;

use Test::More;
use Try::Tiny;

use Moonpig::Util qw(same_day_next_month);

for my $month (1..12) {
  for my $day (1..28) {
    my $now = Moonpig::DateTime->new(
      year => 2001, # Non leap year!
      month => $month,
      day   => $day,
    );

    my $then = same_day_next_month($now);

    note("Expecting: $now + 1 month");
    note("Got:       $then");

    if ($month <= 11) {
      is($then->month, $now->month + 1, 'got next month');
      is($then->year,  $now->year, 'got this year');
    } else {
      is($then->month, $now->month - 11, 'got next month (next year');
      is($then->year,  $now->year + 1,   'got next year for sure');
    }

    is($then->day, $now->day, 'got same day');
  }
}

for my $month (1..12) {
  for my $day (29..31) {
    my $now = try {
      Moonpig::DateTime->new(
        year => 2000, # Non leap year!
        month => $month,
        day   => $day,
      );
    };

    next unless $now;

    my $then = same_day_next_month($now);

    note("Expecting: $now + 2 months, on the first of the month");
    note("Got:       $then");

    if ($month <= 10) {
      is($then->month, $now->month + 2, 'got two months away');
      is($then->year,  $now->year, 'got this year');
    } elsif ($month == 11) {
      is($then->month, 1, 'got january of next year');
      is($then->year,  $now->year + 1,   'got next year for sure');
    } elsif ($month == 12){
      is($then->month, 2, 'got february of next year');
      is($then->year,  $now->year + 1,   'got next year for sure');
    }

    is($then->day, 1, 'got first day of the month');
  }
}

done_testing;
