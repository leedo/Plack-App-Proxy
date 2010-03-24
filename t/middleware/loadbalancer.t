use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Middleware::Proxy::LoadBalancer;
use Test::More;
use Plack::App::Proxy::Test;
use HTTP::Request::Common;

my $app = sub {
    my $env = shift;
    [ 200, [ 'X-PathInfo' => $env->{PATH_INFO} ], [ 'Hello' ] ];
};

test_proxy(
    app   => $app,
    proxy => sub {
        Plack::Middleware::Proxy::LoadBalancer->wrap(
            Plack::App::Proxy->new(),
            backends => "http://$_[0]:$_[1]/backend"
        );
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET '/');
        like $res->header( 'X-PathInfo' ), qr/backend/;
    },
);

test_proxy(
    app   => $app,
    proxy => sub {
        Plack::Middleware::Proxy::LoadBalancer->wrap(
            Plack::App::Proxy->new,
            backends => [
                "http://$_[0]:$_[1]/backend1",
                "http://$_[0]:$_[1]/backend2",
                "http://$_[0]:$_[1]/backend3",
            ],
        );
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET '/');
        like $res->header( 'X-PathInfo' ), qr/backend[1-3]/;
    },
);

test_proxy(
    app   => $app,
    proxy => sub {
        Plack::Middleware::Proxy::LoadBalancer->wrap(
            Plack::App::Proxy->new,
            backends => {
                "http://$_[0]:$_[1]/backend1" =>   0, # won't be selected
                "http://$_[0]:$_[1]/backend2" => 0.1,
                "http://$_[0]:$_[1]/backend3" => 0.2,
            },
        );
    },
    client => sub {
        my $cb = shift;
        my $res = $cb->(GET '/');
        like $res->header( 'X-PathInfo' ), qr/backend[23]/;
    },
);

done_testing;
