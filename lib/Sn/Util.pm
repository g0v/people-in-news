package Sn::Util;
use Sn;

our @EXPORT_OK = qw( nsort_by sort_by uniq_by );

sub nsort_by :prototype(&@) {
    my $cb = shift;
    return map { $_->[1] } sort { $a->[0] <=> $b->[0] } map {[ $cb->($_), $_ ]} @_;
}

sub sort_by :prototype(&@) {
    my $cb = shift;
    return map { $_->[1] } sort { $a->[0] cmp $b->[0] } map {[ $cb->($_), $_ ]} @_;
}

sub uniq_by :prototype(&@) {
    my $cb = shift;
    my %seen;
    my @items;
    for my $item (@_) {
        local $_ = $item;
        my $k = $cb->($item);
        unless ($seen{$k}) {
            $seen{$k} = 1;
            push @items, $item;
        }
    }
    return @items;
}

1;
