use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Test;
use Test::More;

test_psgi
  app => Plack::App::Proxy->new(host => "http://www.google.com/intl/en"),
  client => sub {
    my $cb = shift;
    # The client send the request to encode the response.
    my $req = HTTP::Request->new(
      GET => "http://localhost/index.html", [
        'Accept-Encoding' => 'gzip,deflate', 
        'User-Agent'      => 'Mozilla/5.0',
      ]
    );
    my $res = $cb->($req);
    like $res->headers->header('Content-Encoding'), qr/gzip/, 
         "Recieved the contents gzipped";
  };

done_testing;
