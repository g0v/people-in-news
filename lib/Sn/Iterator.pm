package Sn::Iterator;
use v5.18;
use Moo::Role;

requires 'reify';

has _cursor => (
    is => "rw",
    predicate => 1,
);

has reified => (
    is => "rw",
    default => sub { [ ] }
);

use overload '&{}' => sub {
    my $self = $_[0];
    return sub { $self->next() }
};

sub next {
    my ($self) = @_;

    if ( !$self->_has_cursor || $self->_cursor == @{$self->reified}) {
        $self->reified( $self->reify );
        $self->_cursor(0);
    }

    my $i = $self->_cursor;
    $self->_cursor($i+1);
    return $self->reified->[$i];
}

1;
