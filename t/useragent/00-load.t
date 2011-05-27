
use Test::More;

BEGIN { use_ok('Moonpig::UserAgent') }

my $ua = Moonpig::UserAgent->new({ base_uri => "http://localhost:5001" });

done_testing;
