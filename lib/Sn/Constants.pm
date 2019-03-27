package Sn::Constants;
use utf8;
use strict;
use warnings;

use Exporter 'import';

use Module::Functions;

our %SNRE;
our @EXPORT = ('%SNRE', get_public_functions());

use constant {
    NEWSPAPER_NAMES => [
        '芋傳媒 TaroNews',
        '上報',
        '中央社',
        '蕃新聞',
        '無綫新聞',
        '蘋果日報',
        '自由時報電子報',
        '中國時報',
        '工商時報',
        '旺報',
    ]
};

$SNRE{newspaper_names} = '(?:' . join('|', @{ NEWSPAPER_NAMES() }) . ')';

1;
