use strict;
use warnings;

use Test::More;
use Try::Tiny;

use Moonpig::Util qw(same_day_of_month_next_year);

for my $month (1..12) {
  for my $day (1..28) {
    my $now = Moonpig::DateTime->new(
      year => 2001, # Non leap year!
      month => $month,
      day   => $day,
    );

    my $then = same_day_of_month_next_year($now);

    note("Expecting: $now + 1 year");
    note("Got:       $then");

    is($then->month, $now->month, 'got same month');
    is($then->year,  $now->year + 1, 'got next year');
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

    my $then = same_day_of_month_next_year($now);

    note("Expecting: $now + 1 year and 1 month, on the first of the month");
    note("Got:       $then");

    if ($month <= 11) {
      is($then->month, $now->month + 1, 'got one month away');
      is($then->year,  $now->year + 1, 'got next year');
    } elsif ($month == 12){
      is($then->month, 1, 'got january of year after next');
      is($then->year,  $now->year + 2, 'got year after next for sure');
    }

    is($then->day, 1, 'got first day of the month');
  }
}

done_testing;
