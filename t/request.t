use Plack::App::Proxy;
use Plack::Test;
use Test::More tests => 1;

test_psgi
  app => Plack::App::Proxy->new(host => "http://www.google.com"),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/");
    my $res = $cb->($req);
    like $res->content, qr/Google Search/, "google";
  };
