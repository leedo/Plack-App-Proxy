use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Middleware::Proxy::LoadBalancer;
use Test::More;
use Plack::App::Proxy::Test;

test_proxy(
    proxy => sub {
        Plack::Middleware::Proxy::LoadBalancer->wrap(
            Plack::App::Proxy->new(),
            backends => ["http://$_[0]:$_[1]/"]),
    },
    app   => sub {
        my $env = shift;
	ok $env;
        [ 200, [], [ 'Hello' ] ];
    },
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => "http://localhost/" );
        my $res = $cb->($req);
	ok $res;
    },
);

done_testing;
