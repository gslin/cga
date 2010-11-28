package CGA;

use strict;
use warnings;

sub parseKeyword {
    my $str = shift;

    return 1 if $str =~ /(?:海|洋|岸|北|中|南|東).*巡/;
    return 1 if $str =~ /安.*檢/;
    return 1 if $str =~ /(?:一|二|三|四|五|六|七|八|九).*(?:大|總).*隊/;

    return 0;
}

1;
