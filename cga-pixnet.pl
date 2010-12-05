#!/usr/bin/perl

use 5.010;
use CGA;
use Carp;
use Coro;
use Coro::EV;
use Coro::LWP;
use Coro::Timer qw/sleep/;
use Getopt::Std;
use HTML::TreeBuilder;
use HTTP::Cookies;
use JSON;
use JobQueue;
use LWP::UserAgent;
use Log::Log4perl qw/:easy/;
use Object::Destroyer;
use URI;
use strict;
use warnings;

use constant APIBASE => 'http://emma.pixnet.cc.nyud.net';

main();

sub genCookie {
    my $cookie = HTTP::Cookies->new;
    return $cookie;
}

sub genHeader {
    my $h = HTTP::Headers->new;

    $h->header('Accept', 'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8');
    $h->header('Accept-Charset', 'UTF-8,*');
    $h->header('Accept-Language', 'zh-tw,en-us;q=0.7,en;q=0.3');

    return $h;
}

sub genUA {
    my $ua = LWP::UserAgent->new;
    $ua->proxy(['http'], 'http://proxy.hinet.net:80/');

    $ua->default_headers(genHeader());

    $ua->agent('Mozilla/5.0 (Windows; U; Windows NT 5.1; zh-TW; rv:1.9.2.12) Gecko/20101026 Firefox/3.6.12');
    $ua->cookie_jar(genCookie());

    return $ua;
}

sub grubAlbum {
    use vars qw/$albumQueue/;
}

sub grubUser {
    use vars qw/$userQueue/;

    my $username = shift;

    my $ua = genUA();
    my $url = "http://$username.pixnet.net.nyud.net/friend/list";

    for (;;) {
	my $res = $ua->get($url);
	DEBUG sprintf "Receiving %s code %d", $url, $res->code;

	last if !$res->is_success;

	my $body = $res->content;
	DEBUG sprintf 'Receiving %s for %d bytes', $url, length $body;

	last;
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
	    my $v = $albumQueue->get;
	    if (!defined $v) {
		sleep 1;
		next;
	    }

	    my ($username, $id) = @$v;
	    DEBUG sprintf 'albumQueue working on %s/%s (%d available)', $username, $id, $albumQueue->length;

	    grubAlbum($username, $id);
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
}

sub main {
    use vars qw/$albumQueue $userQueue/;
    initParams();

    push(@LWP::Protocol::http::EXTRA_SOCK_OPTS, SendTE => 0);

    $albumQueue = JobQueue->new(glob '~/data/pixnet.albumqueue');
    $userQueue = JobQueue->new(glob '~/data/pixnet.userqueue');

    my $username = shift @ARGV or croak 'Lack of username';
    $userQueue->put(lc $username);

    grubWorker();

    schedule;
}

__END__
