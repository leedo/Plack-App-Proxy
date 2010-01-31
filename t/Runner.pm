package t::Runner;
use strict;
use warnings;
use Carp;
use Plack::App::Proxy;
use Plack::Loader;
use Plack::Test;
use Test::More;
use Test::TCP;
use base Exporter::;
our @EXPORT = qw(test_proxy run_tests);

sub test_proxy {
  my %args = @_;

  local $Plack::Test::Impl = 'Server';

  my $client = delete $args{client} or croak "client test code needed";
  my $app    = delete $args{app}    or croak "app needed";
  my $proxy  = delete $args{proxy}  or croak "proxy needed";
  my $host   = delete $args{host} || '127.0.0.1';

  test_tcp(
    client => sub {
      my $port = shift;
      test_psgi(
          app => $proxy->( $host, $port ),
          client => $client,
          host => $host,
      );
    },
    server => sub {
      my $port = shift;

      # Use an ordinary server.
      local $ENV{PLACK_SERVER} = 'Standalone';

      my $server = Plack::Loader->auto(port => $port, host => $host);
      $server->run( $app );
    },
  );
}

sub run_tests {
  my $server_type = $_[0];

  local $ENV{PLACK_SERVER} = $server_type;

  # regular static proxy
  test_proxy(
    proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]") },
    app   => sub {
      my $env = shift;
      is $env->{PATH_INFO}, '/index.html', 'PATH_INFO accessed';
      return [ 200, [], [ ('x') x 123, ('y') x 111 ] ];
    },
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(GET => "http://localhost/index.html");
      my $res = $cb->($req);
      ok $res->is_success, "Check the status line.";
      is $res->content, ('x' x 123) . ('y' x 111), "static proxy";
    },
  );

  # Get the proxy host from the Host header
  {
    my ( $app_host, $app_port );
    test_proxy(
      proxy => sub {
        # save the app's host and port for client.
        ( $app_host, $app_port ) = @_;

        my $app = Plack::App::Proxy->new->to_app;
        sub {
            my $env = shift;
            # Host callback returns forbidden response instead of host
            return [ 403, [], [ "forbidden" ] ]
                if $env->{PATH_INFO} =~ m(^/secret);
            $env->{'plack.proxy.remote'} = 'http://' . $env->{HTTP_HOST};
            $app->($env);
        };
      },
      app   => sub { [ 200, [], ["WORLD"] ] },
      client => sub {
        my $cb = shift;
        my $req1 = HTTP::Request->new(
          GET => "http://localhost/index.html", 
          [ Host => "$app_host:$app_port" ]
        );
        my $res1 = $cb->($req1);
        is $res1->content, "WORLD", "dynamic host";

        my $req2 = HTTP::Request->new(GET => "http://localhost/secret/");
        my $res2 = $cb->($req2);
        is $res2->code, 403, "dynamic host forbidden reponse";
      },
    );
  }

  # Don't rewrite the Host header
  test_proxy(
    proxy => sub { Plack::App::Proxy->new(
      remote => "http://$_[0]:$_[1]", preserve_host_header => 1,
    ) },
    app    => sub {
      my $env = shift;
      is $env->{HTTP_HOST}, "__TEST__", "preserve host header";
      [ 200, [], [ 'DUMMY' ] ];
    },
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(
        GET => "http://localhost/", [Host => "__TEST__"]);
      my $res = $cb->($req);
      is $res->code, 200, "success the request.";
    },
  );

  # Get the full URL from a middleware. This example is an open proxy, don't do this!
  {
    my ( $app_host, $app_port );
    test_proxy(
      proxy => sub {
        # save the app's host and port for client.
        ( $app_host, $app_port ) = @_;
        my $app = Plack::App::Proxy->new->to_app;
        sub {
          my $env = shift;
          my ( $url ) = ( $env->{PATH_INFO} =~ m(^\/(https?://.*)) )
              or return [ 403, [], [ "forbidden" ] ];
          $env->{'plack.proxy.url'} = $url;
          $app->($env);
        };
      },
      app   => sub { [ 200, [], ["HELLO"] ] },
      client => sub {
        my $cb = shift;
        my $req1 = HTTP::Request->new(
          GET => "http://localhost/http://$app_host:$app_port/"
        );
        my $res1 = $cb->($req1);
        is $res1->content, "HELLO", "url callback";

        my $req2 = HTTP::Request->new(GET => "http://localhost/index.html");
        my $res2 = $cb->($req2);
        is $res2->code, 403, "dynamic URL forbidden reponse";
      },
    );
  }

  # with QUERY_STRING
  test_proxy(
    proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]") },
    app   => sub {
      my $env = shift;
      is $env->{QUERY_STRING}, 'k1=v1&k2=v2';
      return [ 200, [], [ "HELLO" ] ];
    },
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(
        GET => "http://localhost/proxy/?k1=v1&k2=v2"
      );
      my $res = $cb->($req);
      is $res->content, 'HELLO';
    },
  );

  # avoid double slashes
  test_proxy(
    proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]/") },
    app   => sub {
      my $env = shift;
      return [ 200, [], [ $env->{PATH_INFO} ] ];
    },
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(
        GET => "http://localhost/foo",
      );
      my $res = $cb->($req);
      is $res->content, '/foo';
    },
  );
}

1;
