#!/usr/bin/env perl
use Sn;
use Sn::ArticleIterator;

use Hijk;
use Mojo::JSON qw(encode_json);
use Getopt::Long qw(GetOptions);
# use Encode qw(encode_utf8);
# use UUID::Tiny qw(create_uuid_as_string);

use Path::Tiny;
exit main();

sub main {
    my %opts;
    GetOptions(
        \%opts,
        "db|d=s"
    );
    die "--db <DIR> is needed" unless $opts{db} && -d $opts{db};

    my @docs = ();
    my $id   = 10000;
    my $iter = Sn::ArticleIterator->new(db_path => $opts{db});
    while ( my $article = $iter->() ) {
        my %doc = %$article;
        $doc{id} = "".($id++);
        delete($doc{substrings});
        push @docs, \%doc;

        if (@docs > 10000) {
            meilisearch_add_documents(\@docs);
            @docs = ();
        }
    }
    if (@docs) {
        meilisearch_add_documents(\@docs);
    }

    return 0;
}

sub meilisearch_add_documents {
    my $docs = shift;

    my $res = Hijk::request({
        method => 'POST',
        host   => 'localhost',
        port   => '7700',
        path   => '/indexes/articles/documents',
        head   => [
            'Content-Type' => 'application/json'
        ],
        body => encode_json($docs),
        parse_chunked => 1,
    });
    say encode_json($res);
    die "Expecting an 'OK' response" unless $res->{status} =~ /^2/;
}
