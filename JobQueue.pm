package JobQueue;

use strict;
use warnings;

sub get {
    my $self = shift;
    return shift @{$self->{jqa}};
}

sub length {
    my $self = shift;
    return scalar @{$self->{jqa}};
}

sub new {
    bless {jq => {}, jqa => []};
}

sub put {
    my $self = shift;
    my $id = shift;

    return if defined $self->{jq}->{$id};

    $self->{jq}->{$id} = 0;
    push @{$self->{jqa}}, $id;
}

1;
