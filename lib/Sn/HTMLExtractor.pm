package Sn::HTMLExtractor {
    use Moo;

    use List::Util qw(max);
    use HTML::ExtractContent;
    use Mojo::DOM;
    use Types::Standard qw(Str InstanceOf);
    use Encode qw(decode);

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

    sub content_text {
        my ($self) = @_;

        my $extractor = HTML::ExtractContent->new;

        my ($content_dom, $el);
        if ($el = $self->dom->at('article')) {
            $content_dom = Mojo::DOM->new('<body>' . $extractor->extract("$el")->as_html . '</body>');
        } else {
            $content_dom = Mojo::DOM->new('<body>' . $extractor->extract($self->html)->as_html . '</body>');
        }

        my $text = $content_dom->all_text;
        for ($text) {
            s/\x{fffd}//g;
            s/\t/ /gs;
            s/\r\n/\n/gs;
            s/\n +/\n/gsm;
            s/ +\n/\n/gsm;
            s/\n\n\n/\n\n/gsm;
        }

        my @paragraphs = split /\n\n/, $text;
        return undef unless @paragraphs;

        my $maxl = max( map { length($_) } @paragraphs );
        if ($maxl < 60) {
            # err "[$$] Not enough contents";
            return undef;
        }

        return $text;
    }
};

1;
