package Sn::ArticleIterator;
use Moo;
use Types::Standard qw(Str);
use Types::Common::Numeric qw(PositiveOrZeroNum);
use File::Next;
use JSON::XS qw(decode_json);
use Try::Tiny;
use PerlIO::via::gzip;

with 'Sn::Iterator';

has db_path => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has _file_iter => (
    is => 'lazy',
);

sub _build__file_iter {
    my ($self) = @_;
    return File::Next::files(
        +{ file_filter => sub { /\.jsonl(\.gz)?$/ } },
        $self->db_path,
    );
}

sub reify {
    my ($self) = @_;
    my $files = $self->_file_iter();

    my @objs;

    while (@objs < 1000) {
        my $fn = $self->_file_iter->() or last;

        my $fh;
        if ($fn =~ /\.gz$/) {
            open $fh, '<:via(gzip)', $fn;
        } else {
            open $fh, '<', $fn;
        }

        while(<$fh>) {
            chomp;
            try {
                my $o = decode_json($_);
                push @objs, $o;
            };                  # Ignore Errors
        }
    }

    $self->reified(\@objs);
    $self->_cursor(0);

    return $self;
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
