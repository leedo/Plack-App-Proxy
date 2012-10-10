use strict;
use warnings;
use Test::More;
use Plack::App::Proxy;
use Plack::App::Proxy::Test;
use Plack::Middleware::Lint;

test_proxy(
  proxy => sub { Plack::Middleware::Lint->wrap(
    Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]")
  )},
  app   => sub {
    return [ 200, ["Content-Type", "text/plain", "Status", "200 OK"], [ "Hi" ]];
  },
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/");
    my $res = $cb->($req);
    ok $res->is_success;
  },
);

done_testing;
