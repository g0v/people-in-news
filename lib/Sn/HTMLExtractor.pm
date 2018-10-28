package Sn::HTMLExtractor {
    use Moo;

    use List::Util qw(max);
    use HTML::ExtractContent;
    use Mojo::DOM;
    use Types::Standard qw(Str InstanceOf);

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

        my $content_dom;
        if (my $el = $self->dom->at('article')) {
            $content_dom = Mojo::DOM->new('<body>' . $extractor->extract("$el")->as_html . '</body>');
        } else {
            $content_dom = Mojo::DOM->new('<body>' . $extractor->extract($self->html)->as_html . '</body>');
        }

        my $text = $content_dom->find('body > *')->map('all_text')->map(
            sub {
                s/\t/ /g;
                s/\r\n/\n/g;
                s/\n\n/\n/g;
                s/\A\s+//;
                s/\s+\z//;

                $_ ? $_ : ();
            }
        )->join("\n\n");

        unless ($text) {
            return undef;
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
