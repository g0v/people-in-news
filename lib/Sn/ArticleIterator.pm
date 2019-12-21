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

has _current_fh => (
    is => 'rw',
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

sub _next_file {
    my ($self) = @_;
    my $file = $self->_file_iter->();
    $self->current_file($file);

    my $fh;
    if ($file =~ /\.gz$/) {
        open $fh, '<:via(gzip)', $file;
    } else {
        open $fh, '<:', $file;
    }
    $self->_current_fh($fh);

    return ($file, $fh);
}

sub reify {
    my ($self) = @_;

    my @objs;

    my $fh = $self->_current_fh();
    unless ($fh) {
        $self->_next_file;
        $fh = $self->_current_fh();
        return unless $fh;
    }

    while (@objs < 1000) {
        if (defined( my $line = <$fh>)) {
            chomp($line);
            try {
                push @objs, decode_json($line);
            };
        }
        else {
            (undef, $fh) = $self->_next_file;
            last unless $fh;
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
