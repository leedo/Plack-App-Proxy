use Plack::App::Proxy;
use Plack::Test;
use Test::More tests => 5;

# regular static proxy
test_psgi
  app => Plack::App::Proxy->new(host => "http://www.google.com/intl/en"),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/index.html");
    my $res = $cb->($req);
    like $res->content, qr/Google Search/, "static proxy";
  };

# Get the proxy host from the Host header
test_psgi
  app => Plack::App::Proxy->new(host => sub {
    my $env = shift;
    return $env->{HTTP_HOST};
  }),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(
      GET => "http://localhost/index.html", [Host => "www.google.com"]);
    my $res = $cb->($req);
    is $res->request->header("host"), "www.google.com", "dynamic host";
  };

# Host callback returns forbidden response instead of host
test_psgi
  app => Plack::App::Proxy->new(host => sub {[403, [], ["forbidden"]]}),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/");
    my $res = $cb->($req);
    is $res->code, 403, "dynamic host forbidden reponse";
  };

# Don't rewrite the Host header
test_psgi
  app => Plack::App::Proxy->new(
    host => "http://www.google.com/intl/en",
    preserve_host_header => 1,
  ),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(
      GET => "http://localhost/", [Host => "__TEST__"]);
    my $res = $cb->($req);
    is $res->request->header("host"), "__TEST__", "preserve host header";
  };

# Get the full URL from a callback. This example is an open proxy, don't do this!
test_psgi
  app => Plack::App::Proxy->new(url => sub {
    my $env = shift;
    my ($host) = ($env->{PATH_INFO} =~ /^\/(.+)/);
    return $host;
  }),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/http://www.google.com/intl/en/");
    my $res = $cb->($req);
    like $res->content, qr/Google Search/, "url callback";
  };
