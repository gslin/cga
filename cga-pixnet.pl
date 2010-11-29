#!/usr/bin/perl

use 5.010;
use CGA;
use Carp;
use Coro;
use Coro::EV;
use Coro::LWP;
use Coro::Timer qw/sleep/;
use Getopt::Std;
use LWP::UserAgent;
use Log::Log4perl qw/:easy/;
use strict;
use warnings;

main();

sub initParams {
    my %args;
    my $debug = 0;
    my $verbose = 0;

    getopts 'dv', \%args;

    $debug = 1 if defined $args{d};
    $verbose = 1 if defined $args{v};

    if ($debug > 0) {
	Log::Log4perl->easy_init($DEBUG);
    } elsif ($verbose > 0) {
	Log::Log4perl->easy_init($INFO);
    } else {
	Log::Log4perl->easy_init($WARN);
    }
}

sub main {
    initParams();
}

__END__
