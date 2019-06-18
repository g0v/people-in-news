package Sn::ES;
use v5.18;
use Moo;
use UUID::Tiny qw(create_uuid_as_string);
use Elastijk;

has elastijk => (
    is => 'lazy',
);

sub _build_elastijk {
    my $es = Elastijk->new( host => 'localhost', port => 9200 );

    my ($status, $res) = $es->get();
    if ($res->{version}{number} !~ /^7\./) {
        die 'ABORT: Elasticsearch server version must be 7.x.'
    }

    return $es;
}

sub create_article_index {
    my ($self) = @_;
    return if $self->elastijk->exists( index => 'sn_articles' );

    my $Text = { type => 'text' };
    my ($status, $res) = $self->elastijk->put(
        index => 'sn_articles',
        body => {
            settings => {
                number_of_replicas => 0,
            },
            mappings => {
                properties => {
                    journalist   => $Text,
                    dateline     => $Text,
                    content_text => $Text,
                    title        => $Text,
                    url => { type => 'keyword' },
                }
            }
        }
    );

    if ($status eq '200') {
        say 'Created';
    } else {
        say 'Failed: ' . encode_json($res);
    }

    return 1;
}

sub index_one_article {
    my ($self, $article) = @_;
    my $uuid = create_uuid_as_string;

    my ($status, $res) = $self->elastijk->put(
        index => 'sn_articles',
        type  => '_doc',
        id => $uuid,
        body => {
            journalist   => $article->{journalist},
            dateline     => $article->{dateline},
            content_text => $article->{content_text},
            title        => $article->{title},
            url          => $article->{url},
        }
    );
    
    if ($status !~ /^2/) {
        say 'Failed: ' . $status . ': ' . encode_json($res);
        return 1;
    }
    return 0;
}

1;
