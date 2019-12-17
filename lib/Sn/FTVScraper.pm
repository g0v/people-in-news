use v5.18;
package Sn::FTVScraper {
    use Moo;
    use Mojo::UserAgent;
    use Mojo::DOM;
    use Sn;

    use constant URL_APIBASE => 'https://ftvapi.azurewebsites.net';

    use constant {
        URL_RE_LP => qr(^ (?: https://www.ftvnews.com.tw/news/detail/ | https://news.ftv.com.tw/API/MetaInfo.aspx\?id= ) ([^\s\/]+)$)x,
        URL_NEWSCONTENT  => URL_APIBASE . q(/api/FtvGetNewsContent?id={id}),
    };

    sub discover {
        my ($self) = @_;
        my @links;
        my $ua = Sn::ua();

        $ua->get('https://www.ftvnews.com.tw/');
        $ua->get('https://www.ftvnews.com.tw/news/popnews');
        my $tx = $ua->get('https://ftvapi.azurewebsites.net/api/FtvGetNewsCate');
        my @ids = map { $_->{ID} } @{ $tx->result->json };
        my $tmpl = q(https://ftvapi.azurewebsites.net/api/FtvGetNews?Cate={id}&Page=1&Sp=18);
        for my $id (@ids) {
            my $url = $tmpl =~ s/\{id\}/${id}/r;
            my $tx = $ua->get($url);
            my $items = $tx->result->json('/ITEM');
            push @links, map { $_->{WebLink} } @$items;
        }

        return { links => \@links };
    }

    sub scrape {
        my ($self, $url) = @_;
        return undef unless $url =~ URL_RE_LP;
        my $id = $1;

        my $url_newscontent = URL_NEWSCONTENT =~ s/{id}/${id}/r;

        my $ua = Sn::ua();

        $ua->get($url);
        my $tx = $ua->get($url_newscontent);

        my $article = {
            t_fetched    => (0+ time()),
            url          => "https://www.ftvnews.com.tw/news/detail/" . $id,
        };

        my $o = $tx->result->json('/ITEM/0');
        my $c = $o->{Preface} . "\n\n" . $o->{Content};
        my $text = _html2text($c);

        $article->{title}        = $o->{Title};
        $article->{dateline}     = $o->{CreateDate};
        $article->{substrings}   = Sn::extract_substrings([ $o->{Title}, $text ]);
        $article->{content_text} = $text;
        $article->{t_extracted}  = (0+ time());
        $article->{journalist}   = undef; 
        return $article;
    }

    sub _html2text {
        my ($html) = @_;
        my $dom = Mojo::DOM->new($html);
        return $dom->all_text;
    }
};

1;
