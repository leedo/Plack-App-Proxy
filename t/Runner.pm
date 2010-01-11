use strict;
use warnings;
use Carp;
use Plack::App::Proxy;
use Plack::Middleware::Deflater;
use IO::Handle::Util qw(:io_from);
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
    proxy => sub { Plack::App::Proxy->new(host => "http://$_[0]:$_[1]/") },
    app   => sub { [ 200, [], [ ('x') x 123, ('y') x 111 ] ] },
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(GET => "http://localhost/index.html");
      my $res = $cb->($req);
      ok $res->is_success, "Check the status line.";
      is $res->content, ('x' x 123) . ('y' x 111), "static proxy";
    },
  );

  # Receive the encoded contents.
  test_proxy(
    proxy => sub { Plack::App::Proxy->new(host => "http://$_[0]:$_[1]/") },
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

  # Get the proxy host from the Host header
  {
    my ( $app_host, $app_port );
    test_proxy(
      proxy => sub {
        # save the app's host and port for client.
        ( $app_host, $app_port ) = @_;
        Plack::App::Proxy->new( host => sub {
          my $env = shift;
          return 'http://' . $env->{HTTP_HOST} . '/';
        } );
      },
      app   => sub { [ 200, [], ["WORLD"] ] },
      client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new(
          GET => "http://localhost/index.html", 
          [ Host => "$app_host:$app_port" ]
        );
        my $res = $cb->($req);
        is $res->content, "WORLD", "dynamic host";
      },
    );
  }

  # Host callback returns forbidden response instead of host
  test_proxy(
    proxy  => sub { Plack::App::Proxy->new( 
      host => sub { [ 403, [], [ "forbidden" ] ] },
    ) },
    app    => sub { [ 200, [], [ 'DUMMY' ] ] },
    client => sub {
      my $cb = shift;
      my $req = HTTP::Request->new(GET => "http://localhost/");
      my $res = $cb->($req);
      is $res->code, 403, "dynamic host forbidden reponse";
    },
  );

  # Don't rewrite the Host header
  test_proxy(
    proxy => sub { Plack::App::Proxy->new(
      host => "http://$_[0]:$_[1]/", preserve_host_header => 1,
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

  # Get the full URL from a callback. This example is an open proxy, don't do this!
  {
    my ( $app_host, $app_port );
    test_proxy(
      proxy => sub {
        # save the app's host and port for client.
        ( $app_host, $app_port ) = @_;
        Plack::App::Proxy->new( url => sub {
          my $env = shift;
          my ( $host ) = ( $env->{PATH_INFO} =~ /^\/(.+)/ );
          return $host;
        } );
      },
      app   => sub { [ 200, [], ["HELLO"] ] },
      client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new(
          GET => "http://localhost/http://$app_host:$app_port/"
        );
        my $res = $cb->($req);
        is $res->content, "HELLO", "url callback";
      },
    );
  }

}

1;
