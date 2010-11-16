#!/usr/bin/perl

use 5.010;
use Carp;
use Getopt::Std;
use HTTP::Cookies;
use HTTP::Request;
use JobQueue;
use LWP::UserAgent;
use Log::Log4perl qw/:easy/;
use URI;
use pQuery;

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

sub getURL
{
    use vars qw/$ua/;

    my $url = shift;
    my $uri = URI->new($url);

    $ua->cookie_jar(genCookie());
    my $res = $ua->request(HTTP::Request->new(GET => $uri));

    if ($res->code >= 900) {
	WARN sprintf '%s code %d', $uri->as_string, $res->code;
	croak 'Blocked';
    } elsif ($res->code >= 300) {
	DEBUG sprintf '%s code %d', $uri->as_string, $res->code;
	return '';
    }

    return $res->content;
}

sub grubUsername
{
    state %cacheUsername;
    use vars qw/$q/;

    my $username = lc shift;

    # 判斷是否有抓過
    if ($username ~~ %cacheUsername) {
	DEBUG "$username (cached)";
	return;
    }

    # 先設定 cached 以免下面程式失敗時造成 loop
    $cacheUsername{$username} = 1;

    INFO "Grub $username";

    my $url = SITEBASE . "/album/$username";

    my $uri = URI->new($url);
    my $content = getURL($uri);

    # 如果沒有內容就直接離開
    return if '' eq $content;

    # 先拉出 #friendlist options
    my $options = pQuery($content)->find('#friendlist option');
    DEBUG sprintf "$username (%d results)", $options->length;

    $options->each(sub {
	my $v = $_->getAttribute('value') // return;
	$q->put(lc $v);
    });

    # 找下一頁
    for (my $page = 1;; $page++) {
	DEBUG "$username (page $page)";

	pQuery($content)->find('#ad_square .small-c a')->each(sub {
	    my $text = pQuery($_)->text;

	    foreach my $keyword (qr{(北|中|南|東|海).*巡}, qr{安.*檢}, qr{署.*部}) {
		if ($text =~ $keyword) {
		    say sprintf "%s - %s", $uri, $text;
		    last;
		}
	    }
	});

	my $nextPage = pQuery($content)->find('#next');
	last if 0 == $nextPage->length;

	$uri = $uri->new_abs($nextPage->get(0)->getAttribute('href'), $uri);
	$content = getURL($uri);
    }
}

sub initLog
{
    use vars qw/$debug $log $verbose/;

    if ($debug > 0) {
	$log = Log::Log4perl->easy_init($DEBUG);
    } elsif ($verbose > 0) {
	$log = Log::Log4perl->easy_init($INFO);
    } else {
	$log = Log::Log4perl->easy_init($WARN);
    }
}

sub initParams
{
    use vars qw/$debug $proxy $verbose/;

    my %args;

    $debug = $verbose = 0;
    $proxy = 'http://proxy.hinet.net:80/';

    getopts 'dp:v', \%args;

    $debug = 1 if 'd' ~~ %args;
    $proxy = $args{p} if 'p' ~~ %args;
    $verbose = 1 if 'v' ~~ %args;
}

sub initUA
{
    use vars qw/$proxy $ua/;

    $ua = LWP::UserAgent->new;
    $ua->agent('Mozilla/5.0');
    $ua->proxy(['http'], $proxy) if '' ne $proxy;
    $ua->cookie_jar(genCookie());
}

sub main
{
    use vars qw/$q/;

    initParams();

    my $username = shift @ARGV // croak 'Username empty';

    initLog();
    initUA();

    $q = JobQueue->new;
    $q->put(lc $username);

    while (my $username = $q->get) {
	grubUsername($username);
    }
}

__END__
