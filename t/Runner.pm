use strict;
use warnings;
use Plack::App::Proxy;
use Plack::Test;
use Test::More;
use base Exporter::;
our @EXPORT = qw(run_tests);

sub run_tests {
  my $server_type = $_[0];

  local $Plack::Test::Impl = 'Server';
  local $ENV{PLACK_SERVER} = $server_type;

  # regular static proxy
  test_psgi
    app => Plack::App::Proxy->new(host => "http://www.google.com/intl/en"),
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(GET => "http://localhost/index.html");
      my $res = $cb->($req);
      ok $res->is_success, "Check the status line.";
      like $res->content, qr/Google Search/, "static proxy";
      like $res->content, 
           qr(<html[^>]*>)sm, 
           "Should have a html tag.";
      unlike $res->content, 
           qr(<html[^>]*>.*<html[^>]*>)sm, 
           "Shouldn't have more than two html tags.";
    };

  # Receive the encoded contents.
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
}

1;
