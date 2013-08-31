use strict;
use warnings;
use Test::More;
use Plack::App::Proxy;
use Plack::App::Proxy::Test;

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

# redirect
test_proxy(
  proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]") },
  app   => sub {
    my $env = shift;
    if( $env->{PATH_INFO} eq '/index.html' ){
      return [ 302, [
        Location => 'http://' . $env->{HTTP_HOST} . '/hello.html' 
        ], [] ];
    }
    return [ 200, [], [ "HELLO" ] ];
  },
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new( GET => "http://localhost/index.html" );
    my $res = $cb->($req);
    like $res->header( 'Location' ), qr(\bhello\.html), 
         "pass the Location header to the client directly";
  },
);

# Don't freeze on servers without psgi.nonblocking supports.
test_proxy(
  proxy => sub {
    my $proxy = Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]");
    sub {
      my $env = shift;
      if( $env->{PATH_INFO} eq '/error' ){
        $env->{'plack.proxy.url'} = '!! BADURL to make AE::HTTP error!!' ;
      }
      return $proxy->( $env );
    };
  },
  app   => sub {
    my $env = shift;
    if( $env->{PATH_INFO} eq '/redirect' ){
      return [ 302, [ Location => 'http://d.hatena.ne.jp/hiratara' ], [] ];
    }else{
      return [ 200, [ 'Content-Type' => 'text/plain'], [ "HELLO" ] ];
    }
  },
  client => sub {
    my $cb = shift;
    my $res;

    $res = $cb->(
      HTTP::Request->new( GET => "http://localhost/redirect" )
    );
    is $res->code, 302, 'Success the redirect request.';

    $res = $cb->(
      HTTP::Request->new( GET => "http://localhost/error" )
    );
    like $res->code, qr/^(?:400|502)$/, 'Success the error request.';

    $res = $cb->(
      HTTP::Request->new( GET => "http://localhost/" )
    );
    is $res->code, 200, 'Success all requests.';
  },
);

# server tries to set one cookie
test_proxy(
  proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]" ) },
  app   => sub {
    my $env = shift;
    is $env->{PATH_INFO}, '/index.html', 'PATH_INFO accessed';
    return [
        200,
        [
            'Set-Cookie',
            'foo=bar; path=/blah; expires Sun, 31-Aug-2025 11:28:00 GMT; secure; HttpOnly',
        ],
        [ ('x') x 123, ('y') x 111 ]
    ];
  },
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/index.html");
    my $res = $cb->($req);
    ok $res->is_success, "Check the status line.";
    is $res->content, ('x' x 123) . ('y' x 111), "static proxy";
    my @cookies = $res->header( 'Set-Cookie' );
    is $#cookies, 0, 'one cookies sent by server';
  },
);

# server tries to set two cookies
test_proxy(
  proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]" ) },
  app   => sub {
    my $env = shift;
    is $env->{PATH_INFO}, '/index.html', 'PATH_INFO accessed';
    return [
        200,
        [
            'Set-Cookie',
            'foo=bar; path=/blah; expires Sun, 31-Aug-2025 11:28:00 GMT; secure; HttpOnly',
            'Set-Cookie',
            'bar=foo; path=/blah; expires Sun, 31-Aug-2025 11:28:00 GMT; secure; HttpOnly',
        ],
        [ ('x') x 123, ('y') x 111 ]
    ];
  },
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/index.html");
    my $res = $cb->($req);
    ok $res->is_success, "Check the status line.";
    is $res->content, ('x' x 123) . ('y' x 111), "static proxy";
    my @cookies = $res->header( 'Set-Cookie' );
    is $#cookies, 1, 'two cookies sent by server';
  },
);

# server tries to set four cookies
test_proxy(
  proxy => sub { Plack::App::Proxy->new(remote => "http://$_[0]:$_[1]" ) },
  app   => sub {
    my $env = shift;
    is $env->{PATH_INFO}, '/index.html', 'PATH_INFO accessed';
    return [
        200,
        [
            'Set-Cookie',
            'foo=bar; path=/blah; expires Sun, 31-Aug-2025 11:28:00 GMT; secure; HttpOnly',
            'Set-Cookie',
            'bar=foo',
            'Set-Cookie',
            'third=some value; path=/blah; expires Sun, 31-Aug-2025 11:28:00 GMT; secure; HttpOnly',
            'Set-Cookie',
            'fifth=some othervalue; path=/blah; expires Sun, 31-Aug-2025 11:28:00 GMT; secure',
        ],
        [ ('x') x 123, ('y') x 111 ]
    ];
  },
  client => sub {
    my $cb = shift;
    my $req = HTTP::Request->new(GET => "http://localhost/index.html");
    my $res = $cb->($req);
    ok $res->is_success, "Check the status line.";
    is $res->content, ('x' x 123) . ('y' x 111), "static proxy";
    my @cookies = $res->header( 'Set-Cookie' );
    is $#cookies, 3, 'four cookies sent by server';
  },
);


done_testing;
