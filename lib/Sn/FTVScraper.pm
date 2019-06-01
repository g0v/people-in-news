use v5.18;
package Sn::FTVScraper {
    use Moo;
    use Mojo::UserAgent;
    use Mojo::DOM;
    use Mojo::JSON qw(encode_json);
    use Sn;

    use constant {
        URL_RE_LP => qr(^https://www.ftvnews.com.tw/news/detail/([^\s\/]+)$),
        URL_NEWSCONTENT  => q(https://ftvapi.azurewebsites.net/api/FtvGetNewsContent?id={id}),
    };

    sub scrape {
        my ($self, $url) = @_;
        return undef unless $url =~ URL_RE_LP;
        my $id = $1;
        my $url_newscontent = URL_NEWSCONTENT =~ s/{id}/${id}/r;

        my $ua = Sn::ua();

        $ua->get($url);
        my $tx = $ua->get($url_newscontent);
        my $o = $tx->result->json('/ITEM/0');
        my $c = $o->{Preface} . "\n\n" . $o->{Content};
        return {
            title => $o->{Title},
            dateline => $o->{CreateDate},
            content_html => $c,
            content_text => _html2text($c),
        }
    }

    sub _html2text {
        my ($html) = @_;
        my $dom = Mojo::DOM->new($html);
        return $dom->all_text;
    }
};

1;
