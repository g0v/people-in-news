use v5.18;
use Test2::V0;
use Types::Standard qw(ArrayRef Str);
use Sn;

note 'Verify the structure of %tokens hash';
my $tokens = Sn::load_tokens;

my $isArrayRefOfStr = ArrayRef[Str];

for my $k (keys %$tokens) {
    my $v = $tokens->{$k};
    ok utf8::is_utf8($k), 'token itself is utf8';
    ok $isArrayRefOfStr->($v), 'token is mapped to a list of types';
}

done_testing;
