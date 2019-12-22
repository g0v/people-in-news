package Sn::ArticleIterator;
use Moo;
with 'Sn::Iterator';

use Types::Standard qw(InstanceOf Str CodeRef);
use JSON qw(decode_json);
use Try::Tiny;

use Sn::FileIterator;
use Sn::LineIterator;

has db_path => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has filter_file => (
    is => 'ro',
    isa => CodeRef,
    required => 1,
    default => sub { return sub { 1 } },
);

has line_iter => (
    is => 'lazy',
    isa => InstanceOf['Sn::LineIterator'],
);

sub _build_line_iter {
    my ($self) = @_;
    return Sn::LineIterator->new(
        files => Sn::FileIterator->new(
            dir => $self->db_path,
            filter => $self->filter_file,
        ),
    )
}

sub reify {
    my ($self) = @_;

    my $lines = $self->line_iter;
    my (@objs, $line);
    while (@objs < 1000) {
        $line = $lines->();
        last unless defined($line);
        try {
            push @objs, decode_json($line);
        };
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
