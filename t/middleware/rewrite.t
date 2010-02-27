use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Middleware::Proxy::RewriteLocation;
use Test::More;
use LWP::UserAgent;
use t::Runner;

test_proxy(
  proxy => sub {
      Plack::Middleware::Proxy::RewriteLocation->wrap(
          Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]/"),
      ),
  },
  app   => sub {
      my $env = shift;
      if ($env->{PATH_INFO} eq '/redirect') {
          return [ 301, [ Location => 'http://perl.org/' ], [ 'hi' ] ];
      }
      return [
          301,
          [ "Location" => "http://$env->{HTTP_HOST}/redirect", "X-Server-Port" => $env->{SERVER_PORT} ],
          [ 'Redirected' ],
      ];
  },
  client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(GET => "http://localhost/");
      my $res = $cb->($req);
      is $res->code, 301;
      my $port = $res->header('X-Server-Port');
      unlike $res->header('Location'), qr/:$port/;

      $res = $cb->(HTTP::Request->new(GET => 'http://localhost/redirect'));
      is $res->header('Location'), 'http://perl.org/';
  },
);

done_testing;
