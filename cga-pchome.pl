#!/usr/bin/perl

use 5.010;
use CGA;
use Carp;
use Coro;
use Coro::EV;
use Coro::LWP;
use Coro::Timer qw/sleep/;
use Encode;
use Getopt::Std;
use HTML::TreeBuilder;
use HTTP::Headers;
use JobQueue;
use LWP::UserAgent;
use Log::Log4perl qw/:easy/;
use Object::Destroyer;
use URI;
use strict;
use warnings;

use constant SITEBASE => 'http://photo.pchome.com.tw';

main();

sub genHeader {
    my $h = HTTP::Headers->new;

    $h->header('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    $h->header('Accept-Charset', 'UTF-8,*');
    $h->header('Accept-Language', 'zh-tw,en-us;q=0.7,en;q=0.3');

    return $h;
}

sub genUA {
    my $ua = LWP::UserAgent->new;

    $ua->default_headers(genHeader());
    $ua->agent('Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-TW; rv:1.9.2.12) Gecko/20101026 Firefox/3.6.12');

    return $ua;
}

sub grubAlbum {
    my $url = shift;

    my $res = genUA()->get($url);
    DEBUG sprintf "Receiving %s code %d", $url, $res->code;

    return if !$res->is_success;

    my $body = $res->content;
    DEBUG sprintf 'Receiving %s for %d bytes', $url, length $body;

    # 轉成 UTF-8
    Encode::from_to($body, 'big5', 'utf8');

    # FIXME
    #parseAlbum($body, $url);
}

sub grubFriendList {
    my $username = lc shift;
    my $url = URI->new(SITEBASE . "/shin_friend_list.html?nickname=$username");

    my $ua = genUA();

    for (;;) {
	my $res = $ua->get($url);
	DEBUG sprintf "Receiving %s code %d", $url, $res->code;

	return if !$res->is_success;

	my $body = $res->content;
	DEBUG sprintf 'Receiving %s for %d bytes', $url, length $body;

	# 轉成 UTF-8
	Encode::from_to($body, 'big5', 'utf8');

	parseFriendList($body);

	my $html = HTML::TreeBuilder->new_from_content($body);
	my $htmlD = Object::Destroyer->new($html, 'delete');

	my $nextElement = $html->look_down('_tag', 'a', sub {
		$_[0]->as_text =~ /^下一頁/;
	    }) or last;
	$url = $url->new_abs($nextElement->attr('href'), $url);
	$nextElement->delete;
    }
}

sub grubUser {
    my $username = lc shift;

    grubFriendList($username);

    my $url = URI->new(SITEBASE . "/$username");

    my $ua = genUA();

    for (;;) {
	my $res = $ua->get($url);
	DEBUG sprintf "Receiving %s code %d", $url, $res->code;

	last if !$res->is_success;

	my $body = $res->content;
	DEBUG sprintf 'Receiving %s for %d bytes', $url, length $body;

	# 轉成 UTF-8
	Encode::from_to($body, 'big5', 'utf8');

	parseAlbums($url, $body);

	my $html = HTML::TreeBuilder->new_from_content($body);
	my $htmlD = Object::Destroyer->new($html, 'delete');

	my $nextElement = $html->look_down('_tag', 'a', sub {
		$_[0]->as_text =~ /^下一頁/;
	    }) or last;
	$url = $url->new_abs($nextElement->attr('href'), $url);
	$nextElement->delete;
    }
}

sub grubWorker {
    use vars qw/$albumQueue $userQueue/;

    async {
	for (;;) {
	    my $username = $userQueue->get or return;
	    $username = lc $username;

	    DEBUG sprintf 'userQueue working %s (%d available)', $username, $userQueue->length;

	    grubUser($username);
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

    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 0);
}

sub main {
    use vars qw/$albumQueue $userQueue/;
    initParams();

    $albumQueue = JobQueue->new;
    $userQueue = JobQueue->new;

    my $username = shift @ARGV or croak 'Lack of username';
    $userQueue->put(lc $username);

    grubWorker();

    schedule;
}

sub parseAlbums {
    my $url = shift;
    my $body = shift;
}

sub parseFriendList {
    use vars qw/$userQueue/;

    my $body = shift;

    my $html = HTML::TreeBuilder->new_from_content($body);
    my $htmlD = Object::Destroyer->new($html, 'delete');

    foreach my $fa ($html->look_down('id', 'fa')) {
	my $faD = Object::Destroyer->new($fa, 'delete');

	foreach my $friendElement ($fa->look_down('_tag', 'div', 'class', 'tit')) {
	    my $friendElementD = Object::Destroyer->new($friendElement, 'delete');

	    my $friendLink = $friendElement->look_down('_tag', 'a');
	    my $friendLinkE = Object::Destroyer->new($friendLink, 'delete');

	    my $username = lc substr $friendLink->attr('href'), 1;
	    $userQueue->put($username);
	    DEBUG "Find friend $username";
	}
    }
}

__END__
