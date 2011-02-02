use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Builder;
use Plack::Middleware::Proxy::RewriteLocation;
use Test::More;
use Plack::App::Proxy::Test;
use LWP::UserAgent;

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


######

test_proxy(
    proxy => sub {
        my ( $host, $port ) = @_;
        return builder {
            enable 'Proxy::RewriteLocation', url_map => [
                '/foo/bar' => "http://$host:$port/uuuugh",
                '/foo' => "http://$host:$port/noggin",
               ];

            mount '/foo' => Plack::App::Proxy->new( remote => "http://$host:$port/noggin" );
            mount '/foo/bar' => sub { [ 402, [], ['oh hai'] ] };
        };
    },
    app   => sub {
      my $env = shift;

      unless( $env->{PATH_INFO} =~ m!^/noggin! ) {
          return [ 404, [], 'Not found dude!' ];
      }

      if( $env->{PATH_INFO} eq '/noggin/redirect' ) {
          return [ 301, [ Location => 'http://perl.org/' ], [ 'hi' ] ];
      }

      return [
          301,
          [ "Location" => "http://$env->{HTTP_HOST}:80/noggin/redirect", "X-Server-Port" => $env->{SERVER_PORT} ],
          [ 'Redirected' ],
         ];
    },
  client => sub {
      my $cb = shift;

      my $res = $cb->( HTTP::Request->new( GET => "http://localhost:80/foo" ) );
      is $res->code, 301, 'got right status for request at /foo';
      my $port = $res->header('X-Server-Port');
      like $res->header('Location'), qr!http://[^/]+/foo/redirect!, 'got right proxied redirect URL';

      $res = $cb->(HTTP::Request->new(GET => 'http://localhost/foo/redirect'));
      is $res->header('Location'), 'http://perl.org/', 'got right non-proxied redirect URL'
  },
);

done_testing;
