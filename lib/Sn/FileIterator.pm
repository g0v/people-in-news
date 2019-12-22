package Sn::FileIterator;
use Moo;
with 'Sn::Iterator';
use Types::Standard qw(Str CodeRef);
use File::Next ();

has dir => (
    is => 'ro',
    isa => Str,
    required => 1,
);

has _files => (
    is => 'lazy',
    required => 1,
    builder => 1,
);

has filter => (
    is => 'ro',
    isa => CodeRef,
    required => 1,
    default => sub { return sub { 1 } },
);

sub _build__files {
    my $self = $_[0];
    File::Next::files(+{
        file_filter => sub {
            return $self->filter->($_)
        },
    }, $self->dir );
}

sub reify {
    my ($self) = @_;
    my @chunk;
    my $next = $self->_files->();
    if (defined($next)) {
        push @chunk, $next;
    }
    return \@chunk;
}

1;
