use strict;
use warnings;
use Test::More;
use Plack::App::Proxy;
use HTTP::Headers;

my $proxy = Plack::App::Proxy->new;

my $h = HTTP::Headers->new(
  'Content-Type'      => 'text/html',
  'Set-Cookie'        => 'k1=v1; path=/;',
  'Set-Cookie'        => 'k2=v2; path=/;',
  'Transfer-Encoding' => 'cunked',
  'Connection'        => 'X-Hoge ,  Keep-Alive',
  'X-Hoge'            => 'hoge',
  'Keep-Alive'        => 'hoge=10',
);
$proxy->filter_headers( $h );

is_deeply [ $h->header( 'Content-Type' ) ], [ 'text/html' ];
is_deeply [ $h->header( 'Set-Cookie' ) ], [
  'k1=v1; path=/;', 'k2=v2; path=/;',
];
is_deeply [ $h->header( 'Transfer-Encoding' ) ], [];
is_deeply [ $h->header( 'Connection' )        ], [];
is_deeply [ $h->header( 'X-Hoge' )            ], [];
is_deeply [ $h->header( 'Keep-Alive' )        ], [];

done_testing;
