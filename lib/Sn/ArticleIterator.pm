package Sn::ArticleIterator;
use Moo;
use Types::Standard qw(Str CodeRef);
use File::Next;
use JSON qw(decode_json);
use Try::Tiny;
use PerlIO::via::gzip;

with 'Sn::Iterator';

has db_path => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has current_file => (
    is => 'rw',
    isa => Str,
);

has filter_file => (
    is => 'ro',
    isa => CodeRef,
    required => 1,
    default => sub { return sub { 1 } },
);

has _file_iter => (
    is => 'lazy',
);

sub _build__file_iter {
    my ($self) = @_;
    return File::Next::files(
        +{ file_filter => sub {
               /\.jsonl(\.gz)?$/ && $self->filter_file->($_)
           } },
        $self->db_path,
    );
}

sub reify {
    my ($self) = @_;
    my $files = $self->_file_iter();

    my @objs;

    while (@objs < 1000) {
        my $fn = $self->_file_iter->() or last;
        $self->current_file($fn);

        my $fh;
        if ($fn =~ /\.gz$/) {
            open $fh, '<:via(gzip)', $fn;
        } else {
            open $fh, '<', $fn;
        }

        while(<$fh>) {
            chomp;
            try {
                push @objs, decode_json($_);
            };
        }
    }

    return \@objs;
}

1;

__END__

=head1 SYNOPSIS

Sn::ArticleIterator->new(
    db_path => "/var/db/",
);

my $articles = Sn::ArticleIterator->new(
    db_path => "var/db"
);

while (my $article = $articles->next) {
    say $article->{title};
}
