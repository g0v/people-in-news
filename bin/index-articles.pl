#!/usr/bin/env perl
use v5.26;
use warnings;
use Elastijk;
use Mojo::JSON qw(encode_json);
use Getopt::Long qw(GetOptions);
use Encode qw(encode_utf8);
use UUID::Tiny qw(create_uuid_as_string);
use Sn::ArticleIterator;
exit main();

sub main {
    my %opts;
    GetOptions(
        \%opts,
        "db|d=s"
    );
    die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

    my $es = Elastijk->new( host => 'localhost', port => 9200 );
    es_assert_server_version($es);
    es_create_article_index($es);

    my $iter = Sn::ArticleIterator->new(db_path => $opts{db});
    while ( my $article = $iter->() ) {
        my $err = es_index_one_article($es, $article);
        last if $err;
        say encode_utf8( $article->{title} );
    }
    return 0;
}

sub es_assert_server_version {
    my ($es) = @_;
    my ($status, $res) = $es->get();
    if ($res->{version}{number} !~ /^7\./) {
        die 'ABORT: Elasticsearch version must be 7.x.'
    }
}

sub es_create_article_index {
    my ($es) = @_;
    return if $es->exists( index => 'sn_articles' );

    my $Text = { type => 'text' };
    my ($status, $res) = $es->put(
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

sub es_index_one_article {
    my ($es, $article) = @_;
    my $uuid = create_uuid_as_string;

    my ($status, $res) = $es->put(
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
