package Sn::HTMLExtractor {
    use utf8;
    use v5.18;
    use Moo;
    extends 'NewsExtractor::GenericExtractor';

    use Mojo::DOM;
    use Types::Standard qw(Str InstanceOf);

    has html => (
        is => 'ro',
        isa => Str,
        required => 1,
    );

    has dom => (
        is => "lazy",
        isa => InstanceOf['Mojo::DOM'],
    );

    sub _build_dom {
        my ($self) = @_;
        return Mojo::DOM->new($self->html);
    }
};

1;
