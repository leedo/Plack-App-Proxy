use strict;
use warnings;
use Test::Requires qw(
  Plack::Middleware::Deflater
  IO::Handle::Util
);
use IO::Handle::Util qw(:io_from);
use Plack::App::Proxy;
use Test::More;
use Plack::App::Proxy::Test;

# Receive the encoded contents.
test_proxy(
  proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]/") },
  app   => Plack::Middleware::Deflater->wrap(
    # XXX Plack 0.9030 can't deflate an array-ref response.
    sub { [ 200, [], io_from_array [ 'Hello ', 'World', "\n" ] ] },
  ),
  client => sub {
    my $cb = shift;
    # The client send the request to encode the response.
    my $req = HTTP::Request->new(
      GET => "http://localhost/index.html", [
        'Accept-Encoding' => 'gzip,deflate',
      ]
    );
    my $res = $cb->($req);
    like $res->headers->header('Content-Encoding'), qr/gzip/, 
         "Recieved Content-Encoding header";
    is   $res->decoded_content, "Hello World\n",
         "Recieved the contents gzipped";
  },
);

done_testing;
