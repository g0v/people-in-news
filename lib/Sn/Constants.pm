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
        '鉅亨網',
        '新頭殼 Newtalk',
        '上報',
        '中國時報',
        '中央社 CNA',
        '中央社',
        '工商時報',
        '旺報',
        '無綫新聞',
        '自由娛樂',
        '自由時報電子報',
        '芋傳媒 TaroNews',
        '蕃新聞',
        '蕃新聞',
        '蘋果新聞網｜蘋果日報'
        '蘋果日報',
    ],

    CATEGORY_NAMES => [
        '美股',
        '台股新聞',
        '生活',
        '台灣政經',
        '社會',
        '娛樂',
    ],
};

$SNRE{newspaper_names} = '(?:' . join('|', @{ NEWSPAPER_NAMES() }) . ')';

1;
