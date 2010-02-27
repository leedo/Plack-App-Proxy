use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Middleware::Proxy::AddVia;
use Test::More;
use Plack::App::Proxy::Test;

test_proxy(
    proxy => sub {
        Plack::Middleware::Proxy::AddVia->wrap(
            Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]/"),
        ),
    },
    app   => sub {
        my $env = shift;
        like $env->{HTTP_VIA}, qr/^1\.0 ricky, 1\.1 ethel\s*,\s*1\.[01] /;

        [ 200, [ Via => '1.0 lucy' ], [ 'Hello' ] ];
    },
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => "http://localhost/" );
        $req->headers->header( Via => '1.0 ricky, 1.1 ethel');
        my $res = $cb->($req);
        like $res->header( 'Via' ), qr/1\.0 lucy\s*,\s*\b1\.[01] /;
        like $res->header( 'Via' ), qr(${\ quotemeta $req->uri->host});
        like $res->header( 'Via' ), qr(${\ quotemeta $req->uri->port});
    },
);

done_testing;
