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
        'PChome 新聞',
        '一零一傳媒',
        '上報',
        '中國時報',
        '中央社 CNA',
        '中央社',
        '中華日報新聞網',
        '台灣好新聞 TaiwanHot.net',
        '工商時報',
        '新頭殼 Newtalk',
        '旺報',
        '無綫新聞',
        '聯合新聞網',
        '自由娛樂',
        '自由時報電子報',
        '芋傳媒 TaroNews',
        '蕃新聞',
        '蘋果新聞網｜蘋果日報',
        '蘋果日報',
        '鉅亨網',
        'NOWnews 今日新聞',
        '三立新聞網  SETN.COM',
    ],

    CATEGORY_NAMES => [
        '美股',
        '台股新聞',
        '生活',
        '台灣政經',
        '社會',
        '娛樂',
        '國際',
    ],
};

$SNRE{newspaper_names} = '(?:' . join('|', map { qr($_) } @{ NEWSPAPER_NAMES() }) . ')';

1;
