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
	use YAML::Syck;
	warn Dump $env;
        [ 200, [ Via => '1.0 lucy' ], [ 'Hello' ] ];
    },
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => "http://localhost/" );
        my $res = $cb->($req);
	ok $res;
        #like $res->header( 'Via' ), qr/1\.0 lucy\s*,\s*\b1\.[01] /;
        #like $res->header( 'Via' ), qr(${\ quotemeta $req->uri->host});
        #like $res->header( 'Via' ), qr(${\ quotemeta $req->uri->port});
    },
);

done_testing;
