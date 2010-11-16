#!/usr/bin/perl

use 5.010;
use Carp;
use Coro;
use Coro::EV;
use Coro::LWP;
use Coro::Timer qw/sleep/;
use Getopt::Std;
use HTML::TreeBuilder;
use HTTP::Cookies;
use JobQueue;
use LWP::UserAgent;
use Log::Log4perl qw/:easy/;
use Object::Destroyer;
use URI;
use strict;
use warnings;

use constant SITEBASE => 'http://www.wretch.cc';

main();

sub genCookie
{
    my $cookie = HTTP::Cookies->new;
    $cookie->set_cookie(1, 'showall', '1', '/album/', 'www.wretch.cc');

    return $cookie;
}

sub genUA
{
    my $ua = LWP::UserAgent->new;
    $ua->proxy(['http'], 'http://proxy.hinet.net:80/');
    $ua->cookie_jar(genCookie());

    return $ua;
}

sub grubAlbum
{
    my $url = shift;

    my $res = genUA()->get($url);
    return if !$res->is_success;

    my $body = $res->content;
    DEBUG sprintf 'Receiving %s for %d bytes', $url, length $body;

    parseAlbum($body, $url);
}

sub grubUser
{
    my $url = URI->new(shift);

    my $ua = genUA();

    for (;;) {
	my $res = $ua->get($url);
	last if !$res->is_success;

	my $body = $res->content;
	DEBUG sprintf 'Receiving %s for %d bytes', $url, length $body;

	parseFriendList($body);
	parseAlbums($url, $body);

	my $html = Object::Destroyer->new(HTML::TreeBuilder->new_from_content($body), 'delete');
	my $nextElement = $html->look_down('id', 'next') or last;
	$url = $url->new_abs($nextElement->attr('href'), $url);
	$nextElement->delete;
    }
}

sub grubWorker
{
    use vars qw/$albumQueue $userQueue/;

    async {
	for (;;) {
	    my $username = $userQueue->get or return;
	    $username = lc $username;

	    my $url = SITEBASE . "/album/$username";
	    DEBUG sprintf 'userQueue working %s (%d available)', $username, $userQueue->length;

	    grubUser($url);
	    cede;
	}
    };

    async {
	for (;;) {
	    my $albumUrl = $albumQueue->get;
	    if (!defined $albumUrl) {
		sleep 1;
		next;
	    }

	    DEBUG sprintf 'albumQueue working on %s (%d available)', $albumUrl, $albumQueue->length;

	    grubAlbum($albumUrl);
	    cede;
	}
    };
}

sub initParams
{
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

sub main
{
    use vars qw/$albumQueue $userQueue/;
    initParams();

    $albumQueue = JobQueue->new;
    $userQueue = JobQueue->new;

    my $username = shift @ARGV or croak 'Lack of username';
    $userQueue->put(lc $username);

    grubWorker();

    schedule;
}

sub parseAlbum
{
    my $body = shift;
    my $url = shift;

    my $html = Object::Destroyer->new(HTML::TreeBuilder->new_from_content($body), 'delete');

    my $hit = 0;
    my $k;

    for (;;) {
	my $bannerElement = $html->look_down('id', 'banner') or last;
	if (parseKeyword($bannerElement->as_text)) {
	    $hit = 1;
	    $k = $bannerElement->as_text;
	}
	$bannerElement->delete;
	last;
    }

    do {
	foreach my $smalleElement ($html->look_down('class', 'small-e')) {
	    if (parseKeyword($smalleElement->as_text)) {
		$hit = 1;
		$k = $smalleElement->as_text;
	    }
	    $smalleElement->delete;
	}
    } while (0);

    WARN sprintf "Hit url %s - %s", $url, $k if $hit > 0;
}

sub parseAlbums
{
    use vars qw/$albumQueue/;

    my $url = URI->new(shift);
    my $body = shift;

    my $html = Object::Destroyer->new(HTML::TreeBuilder->new_from_content($body), 'delete');

    foreach my $albumElement ($html->look_down('class', 'side')) {
	$albumElement = Object::Destroyer->new($albumElement, 'delete');

	my $albumLink = $albumElement->look_down('_tag', 'a');
	next if !defined $albumLink;
	$albumLink = Object::Destroyer->new($albumLink, 'delete');

	my $newurl = $url->new_abs($albumLink->attr('href'), $url);
	$albumQueue->put($newurl);
    }
}

sub parseFriendList
{
    use vars qw/$userQueue/;

    my $body = shift;

    my $html = Object::Destroyer->new(HTML::TreeBuilder->new_from_content($body), 'delete');
    my $friendList = $html->look_down('id', 'friendlist') or return;
    DEBUG "test";
    $friendList = Object::Destroyer->new($friendList);

    foreach my $opt ($friendList->look_down('_tag', 'option')) {
	$opt = Object::Destroyer->new($opt, 'delete');
	my $v = $opt->attr('value');

	next if !defined $v;
	next if '' eq $v;

	$userQueue->put(lc $v);
    }
}

sub parseKeyword
{
    my $str = shift;

    return 1 if $str =~ /(?:海|洋|岸|北|中|南|東).*巡/;
    return 1 if $str =~ /安.*檢/;
    return 1 if $str =~ /(?:一|二|三|四|五|六|七|八|九).*(?:大|總).*隊/;

    return 0;
}

__END__
