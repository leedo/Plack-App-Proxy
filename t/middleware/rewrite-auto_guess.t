use strict;
use warnings;
use HTTP::Request::Common qw(GET);
use Plack::App::Proxy;
use Plack::App::Proxy::Test;
use Plack::Builder;
use Test::More;

sub test_rewriting_path($$$) {
    my ($from, $to, $redirect_to) = @_;

    s!/$!! for $from, $to;

    test_proxy(
        proxy => sub {
            my ($host, $port) = @_;
            return builder {
                enable 'Proxy::RewriteLocation';
                mount "$from/" => Plack::App::Proxy->new(
                    remote => "http://$host:$port$to"
                );
            };
        },
        app   => sub {
            my $env = shift;

            if ($env->{PATH_INFO} eq "$to/redirect") {
                return [
                    301, 
                    [Location => "http://$env->{HTTP_HOST}$to$redirect_to"], 
                    ['Redirected']
                ];
            }

            return [
                200,
                [
                    "Content-Type" => "text/plain", 
                    "X-Request-URI"   => $env->{REQUEST_URI}
                ],
                ["OK\n"],
            ];
        },
        client => sub {
            my $cb = shift;

            my $url = "http://localhost$from/redirect";
            # Guess correctly even if the original request contains query
            $url .= $1 if $redirect_to =~ /(\?.+$)/;
            my $res = $cb->(GET $url);

            is $res->code, 301, 'got right status to redirect';
            like $res->header('Location'), 
                 qr!^http://[^/]+\Q$from$redirect_to\E$!,
                 'got right proxied redirect URL';

            $res = $cb->(GET $res->header('Location'));
            like $res->header('X-Request-URI'), qr!^\Q$to$redirect_to\E$!, 
                 'arrived in the target http server'
        },
    );
}

test_rewriting_path "/" => "/", "/goal";
test_rewriting_path "/" => "/foo", "/goal";
test_rewriting_path "/foo" => "/", "/goal";
test_rewriting_path "/foo" => "/bar", "/goal";
test_rewriting_path "/bar" => "/foo/bar", "/goal";
test_rewriting_path "/foo/bar" => "/bar", "/goal";
test_rewriting_path "/foo/goal" => "/foo", "/goal";
test_rewriting_path "/foo" => "/foo/goal", "/goal";
test_rewriting_path "/foo" => "/bar", "/goal?param=999";

done_testing;
