package Sn::ArticleExtractor {
    use utf8;
    use Sn;
    use URI;
    use Encode qw(decode);
    use NewsExtractor::Extractor;

    use Moo;
    has 'tx' => ( is => 'ro', required => 1 );

    sub looks_like_article_page {
        my ($self) = @_;
        my $res = $self->tx->res;
        return 0 unless $res->body;

        my Mojo::URL $url = $self->tx->req->url;
        return 0 if $url->path() eq '/';

        my $dom = $res->dom;
        my $it;
        do {
            ($it = $dom->at('div.search .large-8 .bigtitle') and do { $it->text =~ /SEARCH/ }) or
            ($dom->at('body > #tnl-author')) or
            ($dom->at('div#main article.articles') && $dom->find('div#main > *')->size == 1) or
            $dom->at('ol.breadcrumb li:nth-child(2) a[href="/photocatalog.aspx"]') or
            $dom->at('div.tag-newslist .block_content div[itemtype="http://schema.org/NewsArticle"]') or
            $dom->at('.Section .List .HeadlineTopImage-S a') or
            $dom->at('div.searchResultPanel .newsSearch') or
            $dom->at('#news-list .wrap dl dt a[href^=news_info]') or
            $dom->at('div.listContent ul#myMainList') or
            $dom->at('div.td-big-grid-wrapper h3.td-module-title') or
            $dom->at("div.newsStyle03 dl.newsContent02") or
            $dom->at('#tagNews') or
            $dom->at('.author-section .list-container') or
            ($dom->at('.cate-title header') && ($dom->find('.list-container')->size > 1)) or
            $dom->at('body.channel section.search-result') or
            $dom->at('.clsGetMoreTopics') or
            $dom->at('#aspnetForm .newsimg-area-item-2') or
            $dom->at('ol.breadcrumb span.glyphicon-tags') or
            $dom->at('div#content section.mod_search-result') or
            $dom->at('body.tag main div.posts_list') or
            $dom->at('div#result_list') or
            $dom->at('div[data-desc="新聞列表"] ul.searchlist') or
            $dom->at('dl#author_article_list_list') or
            $dom->at('div.articleGroup section.subArticle') or
            (!$dom->at('.news-artical') && $dom->find('div.newslist-page div.newslist-container a p.newstitle')->size > 3) or
            ($dom->find('div.part_list_2 h3')->size > 3) or
            ($dom->find('main#content div.listing article.type-post')->size > 3) or
            ($dom->find('div[role=main] article.post')->size > 1) or
            ($dom->find('div.posts-holder article.post')->size > 1) or
            $dom->at('body.archive.tag div.post_list') or
            $dom->at('body.node-type-writer .breadcrumb .last a[href^=/author]') or
            $dom->at('h1._uUSu') or
            ( $url->host() eq "www.greatnews.com.tw" and $dom->at("div.container div#focus_are") ) or
            ( $url->host() eq "www.hccg.gov.tw" and $dom->at("img#main_img0") )
        } and return 0;

        if ($_ = $dom->at('h1.entry-title > span')) {
            return 0 if $_->content() =~ /^Tag:/;
        }

        return 1;
    }

    sub extract {
        my ($self) = @_;

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
        @links = keys %seen;

        return (undef, \@links) unless $self->looks_like_article_page;

        my $charset = Sn::tx_guess_charset($tx) or return(undef, \@links);
        my $html = decode($charset, $res->body);

        my $extractor = NewsExtractor::Extractor->new( tx => $tx );

        my $title = $extractor->headline;
        my $text = $extractor->content_text;

        return (undef, \@links) unless $title && $text;

        $article{title}        = "". $title;
        $article{content_text} = "". $text;
        $article{substrings}   = Sn::extract_substrings([ $title, $text ]);
        $article{t_extracted}  = (0+ time());
        $article{dateline}     = $extractor->dateline;
        $article{journalist}   = $extractor->journalist;

        return (\%article, \@links);
    }

};

1;
