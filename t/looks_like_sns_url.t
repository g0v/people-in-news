use v5.18;
use warnings;
use Test2::V0;
use Importer 'Sn::TextUtil' => qw(looks_like_sns_url);

ok looks_like_sns_url(
    'https://accounts.google.com/ServiceLogin?xxx&ooo'
);


ok not looks_like_sns_url(
    'https://accounts1google1com/ServiceLogin?xxx&ooo'
);

done_testing;
