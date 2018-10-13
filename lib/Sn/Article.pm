package Sn::Article {
    use Moo;
    use Types::Standard qw(Str);
    use Types::URI -all;

    has uri => (
        is => "ro",
        isa => Uri,
        required => 1,
    );
    has title => (
        is => "ro",
        isa => Str
        required => 1,
    );
    has content_text => (
        is => "ro",
        isa => Str
        required => 1,
    );
};

1;
