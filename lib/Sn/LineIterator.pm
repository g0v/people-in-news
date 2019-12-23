package Sn::LineIterator;
use Moo;
with 'Sn::Iterator';
use Types::Standard qw(InstanceOf);
use PerlIO::via::gzip;
use Sn::FileIterator;

has files => (
    is => 'ro',
    isa => InstanceOf['Sn::FileIterator'],
    required => 1,
);

has _current_fh => (
    is => 'rw',
);

sub _next_fh {
    my ($self) = @_;
    my $file = $self->files->next;
    return undef unless defined($file);

    my $fh;
    if ($file =~ /\.gz$/) {
        open $fh, '<:via(gzip)', $file;
    } else {
        open $fh, '<:', $file;
    }
    $self->_current_fh($fh);

    return $fh;
}

sub reify {
    my ($self) = @_;
    my @chunk;

    my $fh = ($self->_current_fh() // $self->_next_fh) or return \@chunk;
    while (@chunk < 1000) {
        if (defined( my $line = <$fh> )) {
            chomp($line);
            push @chunk, $line;
        } else {
            $fh = $self->_next_fh;
            last unless defined($fh);
        }
    }

    return \@chunk;
}

1;
