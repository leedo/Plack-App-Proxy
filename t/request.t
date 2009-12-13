use Plack::App::Proxy;
use Plack::Test;
use Test::More tests => 2;

test_psgi
  app => Plack::App::Proxy->new(host => "http://www.google.com"),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/");
    my $res = $cb->($req);
    like $res->content, qr/Google Search/, "google";
  };
  
test_psgi
  app => Plack::App::Proxy->new(
    host => "http://www.google.com/",
    preserve_host_header => 1,
  ),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(
      GET => "http://localhost/", [Host => "__TEST__"]);
    my $res = $cb->($req);
    is $res->request->header("host"), "__TEST__", "preserve host header";
  };