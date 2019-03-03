package Sn::HTMLExtractor {
    use v5.18;
    use Moo;

    use List::Util qw(max);
    use HTML::ExtractContent;
    use Mojo::DOM;
    use Types::Standard qw(Str InstanceOf);
    use Sn::TextUtil qw(normalize_whitespace);

    has html => (
        is => 'ro',
        isa => Str,
        required => 1,
    );

    has dom => (
        is => "lazy",
        isa => InstanceOf['Mojo::DOM'],
    );

    no Moo;

    sub _build_dom {
        my ($self) = @_;
        return Mojo::DOM->new($self->html);
    }

    sub title {
        my ($self) = @_;
        my $title_el = $self->dom->find("title");
        unless ($title_el->[0]) {
            return;
        }

        my $title;
        $title = $title_el->[0]->text."";
        $title =~ s/\r\n/\n/g;
        $title =~ s/\A\s+//;
        $title =~ s/\s+\z//;

        return $title;
    }

    sub dateline {
        my ($self) = @_;
        my $dateline;
        my $guess;

        if ($guess = $self->dom->at("time[itemprop=datePublished][datetime]")) {
            $dateline = $guess->attr('datetime');
        }
        elsif ($guess = $self->dom->at(".reporter time")) {
            $dateline = $guess->text
        }
        elsif ($guess = $self->dom->at("div#articles cite")) {
            $guess->at("a")->remove;
            $dateline = $guess->text;
        }
        elsif ($guess = $self->dom->at("span.time, span.viewtime")) {
            $dateline = $guess->text;
        }
        elsif ($guess = $self->dom->at("header.article-desc time")) {
            $dateline = $guess->text;
        }
        elsif ($guess = $self->dom->at("article.ndArticle_leftColumn div.ndArticle_creat")) {
            ($dateline) = $guess->text =~ m#([0-9]{4}/[0-9]{2}/[0-9]{2} [0-9]{2}:[0-9]{2})#;
        }

        if ($dateline) {
            $dateline = normalize_whitespace($dateline);
        }
        return $dateline;
    }

    sub content_text {
        my ($self) = @_;

        my $extractor = HTML::ExtractContent->new;

        my ($content_dom, $el, $html);
        if ($el = $self->dom->at('article')) {
            $html = $extractor->extract("$el")->as_html;
        } else {
            $html = $extractor->extract($self->html)->as_html;
        }
        $content_dom = Mojo::DOM->new('<body>' . $html . '</body>');
        $content_dom->find('br')->each(sub { $_[0]->replace("\n<br>") });

        my ($text, @paragraphs);
        @paragraphs = map {
            s/\A\s+//s;
            s/\s+\z//s;
            $_ ? $_ : ();
        } $content_dom->find('*')->map('text')->map(
            sub {
                $_ = normalize_whitespace($_);
                s/\r\n/\n/g;
                split /\n\s+\n?/, $_;
            }
        )->each;

        unless (@paragraphs) {
            return;
        }

        if (max( map { length($_) } @paragraphs ) < 30) {
            # err "[$$] Not enough contents";
            return undef;
        }

        return join "\n\n", @paragraphs;
    }
};

1;
