use strict;
use warnings;
use Plack::Test;
use Plack::App::Proxy;
use Test::More tests => 3;

# Do the test with psgi.streaming
use AnyEvent;
$Plack::Test::Impl = 'Server';

test_psgi
  app => Plack::App::Proxy->new(host => "http://www.google.com/intl/en"),
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/index.html");

    my $res = $cb->($req);

    ok $res->is_success, "Check the status line.";
    like $res->content, 
         qr(<html[^>]*>)sm,
         "Should have a html tag.";
    unlike $res->content, 
         qr(<html[^>]*>.*<html[^>]*>)sm,
         "Shouldn't have more than two html tags.";
  };
