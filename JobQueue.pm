package JobQueue;

use strict;
use warnings;

BEGIN {
    eval { use DBM::Deep; };
}

sub DESTROY {
    my $self = shift;

    untie %{$self->{h}} if defined $self->{h};
}

sub get {
    my $self = shift;
    return pop @{$self->{jqa}};
}

sub length {
    my $self = shift;
    return scalar @{$self->{jqa}};
}

sub new {
    my $self = shift;
    my $filename = shift;

    $self = bless {};

    if (defined $filename) {
	my $a = DBM::Deep->new(file => "$filename.a", type => DBM::Deep->TYPE_ARRAY);
	my $h = DBM::Deep->new(file => "$filename.h", type => DBM::Deep->TYPE_HASH);

	$self->{jq} = $h;
	$self->{jqa} = $a;
    } else {
	$self->{jq} = {};
	$self->{jqa} = [];
    }

    return $self;
}

sub put {
    my $self = shift;
    my $id = shift;

    return if defined $self->{jq}->{$id};

    $self->{jq}->{$id} = 0;
    push @{$self->{jqa}}, "$id";
}

sub reput {
    my $self = shift;
    my $id = shift;

    $self->{jq}->{$id} = 0;
    push @{$self->{jqa}}, "$id";
}

1;
