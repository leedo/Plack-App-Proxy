use Plack::App::Proxy;
use Plack::Test;
use Test::More tests => 4;

test_psgi
  app => Plack::App::Proxy->new(host => "http://www.google.com"),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/");
    my $res = $cb->($req);
    like $res->content, qr/Google Search/, "google";
  };

# This example is an open proxy. Don't do this!
test_psgi
  app => Plack::App::Proxy->new(host => sub {
    my $env = shift;
    my ($host) = ($env->{PATH_INFO} =~ /^\/(.+)/);
    return $host;
  }),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/http://www.google.com");
    my $res = $cb->($req);
    like $res->content, qr/Google Search/, "host callback";
  };

test_psgi
  app => Plack::App::Proxy->new(host => sub {[403, [], ["forbidden"]]}),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/http://www.google.com");
    my $res = $cb->($req);
    is $res->code, 403, "host callback response";
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