package Sn::HTMLExtractor {
    use utf8;
    use v5.18;
    use Moo;

    use List::Util qw(max);
    use Encode qw(decode);
    use HTML::ExtractContent;
    use Mojo::DOM;
    use Types::Standard qw(Str InstanceOf Maybe);
    use Sn::TextUtil qw(normalize_whitespace);
    use Sn::Constants qw(%SNRE);

    has html => (
        is => 'ro',
        isa => Str,
        required => 1,
    );

    has dom => (
        is => "lazy",
        isa => InstanceOf['Mojo::DOM'],
    );

    has site_name => (
        is => "lazy",
        isa => Maybe[Str],
    );

    no Moo;

    sub _build_dom {
        my ($self) = @_;
        return Mojo::DOM->new($self->html);
    }

    sub _build_site_name {
        my ($self) = @_;

        my $el = $self->dom->at("meta[property='og:site_name']");
        if ($el) {
            return $el->attr('content');
        }

        return undef;
    }

    sub title {
        my ($self) = @_;

        my $site_name = $self->site_name;
        my ($title, $el);
        my $dom = $self->dom;
        if ($el = $dom->at("#story #news_title, #news_are .newsin_title, .data_midlle_news_box01 dl td:first-child")) {
            $title = $el->text;
        } elsif ($el = $dom->at("meta[property='og:title']")) {
            $title = $el->attr("content");
        } elsif ($el = $dom->at("meta[name='title']")) {
            $title = $el->attr('content');
        } elsif ($el = $dom->at("title")) {
            $title = $el->text;
        } else {
            return;
        }
        $title .= "";

        if ($site_name) {
            $title =~ s/\s* \p{Punct} \s* $site_name \s* \z//x;
        }
        if (defined($title)) {
            $title =~ s/\p{Punct} \s* $SNRE{newspaper_names} \s* \z//x;
            $title =~ s/\A $SNRE{newspaper_names} \s* \p{Punct} \s* //x;
            $title =~ s/\r\n/\n/g;
            $title =~ s/\A\s+//;
            $title =~ s/\s+\z//;
        }
        return $title;
    }

    sub dateline {
        my ($self) = @_;
        my $dateline;
        my $guess;

        my $dom = $self->dom;
        if ($guess = $dom->at("meta[property='article:modified_time'], meta[property='article:published_time'], meta[itemprop=dateModified][content], meta[itemprop=datePublished][content]")) {
            $dateline = $guess->attr('content');
        }
        elsif ($guess = $dom->at("time[itemprop=datePublished][datetime], h1 time[datetime], .func_time time[pubdate]")) {
            $dateline = $guess->attr('datetime');
        }
        elsif ($guess = $dom->at(".reporter time, span.time, span.viewtime, header.article-desc time, .timeBox .updatetime span, .caption div.label-date, .contents_page span.date, .main-content span.date, .newsin_date, .news .date, .author .date, ul.info > li.date > span:nth-child(2), #newsHeadline span.datetime, article p.date, .post-meta > .icon-clock > span, .article_info_content span.info_time, .content time.page-date, .c_time, .newsContent p.time, .story_bady_info_author span:nth-child(1), div.title > div.time, div.article-meta div.article-date, address.authorInfor time, .entry-meta .date a, .author-links .posts-date")) {
            $dateline = $guess->text;
        }
        elsif ($guess = $dom->at("div#articles cite")) {
            $guess->at("a")->remove;
            $dateline = $guess->text;
        }
        elsif ($guess = $dom->at("article.ndArticle_leftColumn div.ndArticle_creat, ul.info li.date, .cpInfo .cp, .nsa3 .tt27")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}[\-/][0-9]{2}[\-/][0-9]{2} [0-9]{2}:[0-9]{2})#;
        }
        elsif ($guess = $dom->at(".news-toolbar .news-toolbar__cell")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}/[0-9]{2}/[0-9]{2})#;
        }
        elsif ($guess = $dom->at(".content .writer span:nth-child(2)")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2})#;
        }
        elsif ($guess = $dom->at("div.contentBox div.content_date")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}\.[0-9]{2}\.[0-9]{2} \| [0-9]{2}:[0-9]{2})#;
        }
        elsif ($guess = $dom->at("div.content-wrapper-right > div > div > div:nth-child(4), span.f12_15a_g2")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2})#;
        }
        elsif ($guess = $dom->at("span#ctl00_ContentPlaceHolder1_News_Label, #ctl00_ContentPlaceHolder1_UpdatePanel2 font[color=darkred]")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}/[0-9]{1,2}/[0-9]{1,2})#;
        }
        elsif ($guess = $dom->at(".news-info dd.date:nth-child(6)")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}年[0-9]{1,2}月[0-9]{1,2}日[0-9]{2}:[0-9]{2})#;
        }
        elsif ($guess = $dom->at("article.entry-content div:nth-child(2)")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}-[0-9]{1,2}-[0-9]{1,2})#;
        }
        elsif ($guess = $dom->at("span.submitted-by")) {
            ($dateline) = $guess->text =~ m#([0-9]{1,2}\s*月\s*[0-9]{1,2}(\s*日\s*)?,\s*[0-9]{4})#x;
        }
        elsif ($guess = $dom->at('#story #news_author')) {
            ($dateline) = $guess->all_text =~ m{\A 【記者.+ 】 (.+) \z}x;
        }
        elsif ($guess = $dom->at('.data_midlle_news_box01 dl dd ul li:first-child')) {
            ($dateline) = $guess->text;
            my ($year, $mmdd) = $dateline =~ /\A ([0-9]{3}) - (.+) \z /x;
            $year += 1911;
            $dateline = $year . '-' . $mmdd;
        }
        elsif ($guess = $dom->at('#details_block .left .date')) {
            $dateline = normalize_whitespace $guess->text;
        }

        if ($dateline) {
            $dateline = normalize_whitespace($dateline);
            if ($dateline =~ /^([0-9]{4})[^0-9]/) {
                if ($1 > ((localtime)[5] + 1900)) {
                    $dateline = undef;
                }
            }
        }

        return $dateline;
    }

    sub journalist {
        my ($self) = @_;

        my $dom = $self->dom;
        my ($ret, $guess);

        if ( $guess = $dom->at('meta[property="og:article:author"]') ) {
            $ret = $guess->attr('content');
        } elsif ( $guess = $dom->at('div.field-item a[href^=/author/], div.story_bady_info_author a, div.content_reporter a[itemprop=author], span[itemprop=author] a, div.author a, div.article-author > h5 > a, div.article-meta > div.article-author > a, div.authorInfo li.authorName > a, .article .writer > p, .info_author, .news-info dd[itemprop=author], .content_reporter a, .story_bady_info_author') ) {
            $ret = normalize_whitespace( $guess->text );
        } elsif ($guess = $dom->at('span.f12_15a_g2')) {
            ($ret) = $guess->text =~ m{／記者 (.+?)／};
        } elsif ($guess = $dom->at('div#yt_container_placeholder + p')) {
            ($ret) = $guess->text =~ m{\A \s* (.+) \s+ 報導 \s+ / }x;
        } elsif ($guess = $dom->at('h4.font_color5')) {
            ($ret) = $guess->all_text =~ m{\A \s* 編輯 \s* (.+) \s+ 報導 }x;
        } elsif ($guess = $dom->at('#story #news_author')) {
            ($ret) = $guess->all_text =~ m{\A 【記者 (.+) ／}x;
        } elsif ($guess = $dom->at('#details_block .left .name')) {
            $ret = normalize_whitespace $guess->text;
        }


        unless ($ret) {
            my $content_text = $self->content_text;
            ($ret) = $content_text =~ m{[记記]者\s*([\s\p{Letter}、]+?)\s*[/╱／]\s*(?:.+)(?:報導|报导)};
            unless ($ret) {
                ($ret) = $content_text =~ m{（(中央社記者.+?日電 | 大纪元记者\p{Letter}+报导 | 記者.+?報導/.+?)）}x;
            }
            unless ($ret) {
                ($ret) = $content_text =~ m# \( ( \p{Letter}+ ／ \p{Letter}+ 報導 ) \) #x;
            }
        }

        return $ret;
    }

    sub content_text {
        my ($self) = @_;
        my ($content_dom, $el, $html);

        # Cleanup some noisy elements that are known to interfere.
        if ($el = $self->dom->at('div#marquee')) {
            $el->remove
        }

        my $extractor = HTML::ExtractContent->new;
        if ($el = $self->dom->at('article')) {
            $html = $extractor->extract("$el")->as_html;
        } else {
            # Remove the generic elements that somehow passed the ExtractContent filter.
            $self->dom->find('p.appE1121, div.sexmask, div.cat-list')->map('remove');

            $html = $extractor->extract( $self->dom->to_string )->as_html;
        }

        $content_dom = Mojo::DOM->new('<body>' . $html . '</body>');
        $content_dom->find('script')->map('remove');
        $content_dom->find('br')->map(replace => "\n");
        $content_dom->find('div,p')->map(append => "\n\n");

        my @paragraphs = grep { $_ ne '' } map { normalize_whitespace($_) } split /\n\n+/, $content_dom->all_text;
        return unless @paragraphs;

        if (my $site_name = $self->site_name) {
            $paragraphs[-1] =~ s/\A \s* \p{Punct}? \s* ${site_name} \s* \p{Punct}? \s* \z//x;
            $paragraphs[-1] =~ s/${site_name}//x;
        }

        $paragraphs[-1] =~ s/\A \s* \p{Punct}? \s* $SNRE{newspaper_names} \s* \p{Punct}? \s* \z//x;

        pop @paragraphs if $paragraphs[-1] eq '';

        if (max( map { length($_) } @paragraphs ) < 30) {
            # err "[$$] Not enough contents";
            return undef;
        }

        return join "\n\n", @paragraphs;
    }
};

1;
