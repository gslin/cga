package JobQueue;

use strict;
use warnings;

BEGIN {
    eval { use NDBM_File; };
}

sub DESTROY {
    my $self = shift;

    untie %{$self->{h}} if defined $self->{h};
}

sub get {
    my $self = shift;
    return shift @{$self->{jqa}};
}

sub length {
    my $self = shift;
    return scalar @{$self->{jqa}};
}

sub new {
    my $self = shift;
    my $filename = shift;

    bless {}, $self;

    if (defined $filename) {
	my %hash;
	tie %hash, 'NDBM_File', $filename, 1, 0;

	$self->{h} = \%hash;

	$self->{jq} = $hash{jq} = {};
	$self->{jqa} = $hash{jqa} = [];
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
    push @{$self->{jqa}}, $id;
}

1;
