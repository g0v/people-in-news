package Sn::ArticleExtractor {
    use utf8;
    use Sn;
    use URI;
    use Encode qw(decode);
    use Sn::HTMLExtractor;

    use Moo;
    has 'tx' => ( is => 'ro', required => 1 );

    sub looks_like_article_page {
        my ($self) = @_;
        my $res = $self->tx->res;
        return 0 unless $res->body;

        my $dom = $res->dom;

        do {
            $dom->at('#aspnetForm .newsimg-area-item-2') or
            $dom->at('ol.breadcrumb span.glyphicon-tags') or
            $dom->at('div#content section.mod_search-result') or
            $dom->at('body.tag main div.posts_list') or
            $dom->at('div#result_list') or
            $dom->at('div[data-desc="新聞列表"] ul.searchlist') or
            $dom->at('dl#author_article_list_list') or
            (!$dom->at('.news-artical') && $dom->find('div.newslist-page div.newslist-container a p.newstitle')->size > 3) or
            ($dom->find('div.part_list_2 h3')->size > 3) or
            ($dom->find('div[role=main] article.post')->size > 1)
        } and return 0;

        if ($_ = $dom->at('h1.entry-title > span')) {
            return 0 if $_->content() =~ /^Tag:/;
        }

        return 1;
    }

    sub extract {
        my ($self) = @_;

        return unless $self->looks_like_article_page;

        my $tx  = $self->tx;
        my $res = $tx->res;

        my %article = (
            t_fetched => (0+ time()),
            url       => ("". $tx->req->url->to_abs),
        );

        my (%seen, @links);
        my $uri = URI->new( "". $tx->req->url->to_abs );
        for my $e ($tx->res->dom->find('a[href]')->each) {
            my $href = $e->attr("href") or next;
            my $u = URI->new_abs("$href", $uri);
            $u->fragment("");
            $u = URI->new($u->as_string =~ s/#$//r);
            next unless (
                $u->scheme =~ /^http/
                && $u->host
                && ($u !~ /\.(?: jpe?g|gif|png|wmv|mp[g234]|web[mp]|pdf|zip|docx?|xls|apk )\z/ix)
                && (! defined($seen{"$u"}))
            );
            $seen{$u} = 1;
        }
        $article{links} = [keys %seen];

        my $charset = Sn::tx_guess_charset($tx) or return;
        my $html = decode($charset, $res->body);

        my $extractor = Sn::HTMLExtractor->new( html => $html );

        my $title = $extractor->title;
        return \%article unless $title;

        my $text = $extractor->content_text;
        return \%article unless $text;

        $article{title}        = "". $title;
        $article{content_text} = "". $text;
        $article{substrings}   = Sn::extract_substrings([ $title, $text ]);
        $article{t_extracted}  = (0+ time());
        $article{dateline}     = $extractor->dateline;
        $article{journalist}   = $extractor->journalist;

        return \%article;
    }

};

1;
