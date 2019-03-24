package Sn::ArticleExtractor {
    use Sn;
    use URI;
    use Encode qw(decode);
    use Sn::HTMLExtractor;

    use Moo;
    has 'tx' => ( is => 'ro', required => 1 );

    sub extract {
        my ($self) = @_;

        my %article;

        my $tx = $self->tx;
        my $res = $tx->res;
        unless ($res->body) {
            # err "[$$] NO BODY";
            return;
        }
        $article{t_fetched} = (0+ time());
        $article{url}       = "". $tx->req->url->to_abs;

        my $charset = Sn::tx_guess_charset($tx) or return;

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

        unless ($article{dateline}) {
            if ($article{content_text} && $article{title}) {
                say STDERR "Faild to extract dateline: $article{url}\n";
            }
            return;
        }

        return \%article;
    }

};

1;
