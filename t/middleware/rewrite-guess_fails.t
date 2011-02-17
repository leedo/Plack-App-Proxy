use strict;
use warnings;
use HTTP::Request::Common qw(GET);
use Plack::App::Proxy;
use Plack::App::Proxy::Test;
use Plack::Builder;
use Test::More;

test_proxy(
    proxy => sub {
        my ($host, $port) = @_;
        return builder {
            # We must specify url_map to avoid auto-guess failure.
            # Otherwise, ":$port" will be changed even if the redirect URL
            # isn't proxied. ("/goal" isn't mapped in this case.)
            enable 'Proxy::RewriteLocation', 
                   url_map => ['/foo' => "http://$host:$port/foo"];
            mount "/foo" => Plack::App::Proxy->new(
                remote => "http://$host:$port/foo"
            );
        };
    },
    app   => sub {
        my $env = shift;
        my $no_proxied_url = "http://$env->{HTTP_HOST}/goal";
        return [
            301, 
            [
                Location => $no_proxied_url,
                'X-Original-Location' => $no_proxied_url,
            ], 
            ['Redirected']
        ];
    },
    client => sub {
        my $cb = shift;

        my $res = $cb->(GET "http://localhost/foo/");
        is $res->code, 301, 'got right status to redirect';
        is $res->header('Location'), $res->header('X-Original-Location'), 
           "Don't rewrite outer paths.";
    },
);


done_testing;
