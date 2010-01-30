package Plack::App::Proxy;

use strict;
use parent 'Plack::Component';
use Plack::Util::Accessor qw/host url preserve_host_header/;
use Plack::Request;
use HTTP::Headers;
use Try::Tiny;
use AnyEvent::HTTP;

our $VERSION = '0.10';

# hop-by-hop headers (see also RFC2616)
my @hop_by_hop = qw(
    Connection Keep-Alive Proxy-Authenticate Proxy-Authorization
    TE Trailer Transfer-Encoding Upgrade
);

sub filter_headers {
    my $self = shift;
    my ( $headers ) = @_;

    # Save from known hop-by-hop deletion.
    my @connection_tokens = $headers->header('Connection');

    # Remove hop-by-hop headers.
    $headers->remove_header( $_ ) for @hop_by_hop;

    # Connection header's tokens are also hop-by-hop.
    for my $token ( @connection_tokens ){
        $headers->remove_header( $_ ) for split /\s*,\s*/, $token;
    }
}

sub build_url_from_env {
    my($self, $env) = @_;

    return $env->{'plack.proxy.url'}
        if exists $env->{'plack.proxy.url'};

    return $self->url->($env)
        if ref $self->url eq 'CODE';

    my $url = $env->{'plack.proxy.host'}
        || (ref $self->host eq 'CODE' ? $self->host->($env) : $self->host)
        or die "Neither proxy host nor URL are configured";

    unless (ref $url eq 'ARRAY') {
        $url .= $env->{PATH_INFO} || '';
        $url .= '?' . $env->{QUERY_STRING} if defined $env->{QUERY_STRING} && length $env->{QUERY_STRING} > 0;
    }

    return $url;
}

sub build_headers_from_env {
    my($self, $env, $req) = @_;

    return $env->{'plack.proxy.headers'}
        if exists $env->{'plack.proxy.headers'};

    my $headers = $req->headers->clone;
    $headers->header("X-Forwarded-For" => $env->{REMOTE_ADDR});
    $headers->remove_header("Host") unless $self->preserve_host_header;
    $self->filter_headers( $headers );

    # Just assume HTTP::Headers is a blessed hash ref
    +{%$headers};
}

sub call {
    my ($self, $env) = @_;

    unless ($env->{'psgi.streaming'}) {
        die "Plack::App::Proxy only runs with the server with psgi.streaming support";
    }

    my $url = $self->build_url_from_env($env);

    # HACK: allow url/host callback to return PSGI response array ref
    return $url if ref $url eq "ARRAY";

    my $req = Plack::Request->new($env);
    my $headers = $self->build_headers_from_env($env, $req);

    my $method  = $env->{'plack.proxy.method'}  || $env->{REQUEST_METHOD};
    my $content = $env->{'plack.proxy.content'} || $req->content;

    return sub {
        my $respond = shift;
        my $cv = AE::cv;
        AnyEvent::HTTP::http_request(
            $method => $url,
            headers => $headers,
            body => $content,
            want_body_handle => 1,
            sub {
                my ($handle, $headers) = @_;
                if (!$handle or $headers->{Status} =~ /^59\d+/) {
                    $respond->([502, ["Content-Type","text/html"], ["Gateway error"]]);
                }
                else {
                    my $writer = $respond->([
                        $headers->{Status},
                        [$self->response_headers($headers)],
                    ]);
                    $handle->on_eof(sub {
                        $handle->destroy;
                        $writer->close;
                        $cv->send;
                        undef $handle;  # free the cyclic reference.
                    });
                    $handle->on_error(sub{});
                    $handle->on_read(sub {
                        my $data = delete $_[0]->{rbuf};
                        $writer->write($data) if defined $data;
                    });
                }

                # Free the reference manually for perl 5.8.x
                # to avoid nested closure memory leaks.
                undef $respond;
            }
        );
        $cv->recv unless $env->{"psgi.nonblocking"};
    }
}

sub response_headers {
    my ($self, $ae_headers) = @_;

    my $headers = HTTP::Headers->new( 
        map { $_ => $ae_headers->{$_} } grep {! /^[A-Z]/} keys %$ae_headers
    );
    $self->filter_headers( $headers );

    my @headers;
    $headers->scan( sub { push @headers, @_ } );

    return @headers;
}

1;

__END__

=head1 NAME

Plack::App::Proxy - proxy requests

=head1 SYNOPSIS

  use Plack::Builder;

  # proxy all requests for /static to 127.0.0.1:80
  builder {
      mount "/static" => Plack::App::Proxy->new(host => "http://127.0.0.1:80")->to_app;
  };

  # Use middleware to modify requests
  my $mw = sub {
      my $app = shift;
      sub {
          my $env = shift;
          ...
          $env->{'plack.proxy.url'} = $url;
          $app->($env);
      };
  };

  builder {
      enable $mw;
      Plack::App::Proxy->new->to_app;
  };

=head1 DESCRIPTION

Plack::App::Proxy is a middleware-aware proxy application for Plack.

=head1 OPTIONS

=over 4

=item host

  Plack::App::Proxy->new(host => 'http://perl.org/')->to_app;

Specifies the remote proxy host. Don't be tricked by the name 'host',
since you can also include the URL path as well.

  builder {
      mount "/example",
          Plack::App::Proxy->new(host => 'http://example.com/app/foo')->to_app;
  };

This makes the request for C</example/bar> proxied to
C<http://example.com/app/foo/bar>.

=head1 preserve_host_header

Preserves the original Host header, which is useful when you do
reverse proxying to the internal hosts.

=back

=head1 MIDDLEWARE CONFIGURATIONS

This application is just like a normal PSGI application and is
middleware aware, which means you can modify proxy requests (and
responses) using Plack middleware stack.

It also supports the following special environment variables:

=over 4

=item plack.proxy.url

Overrides the proxy request URL.

=item plack.proxy.host

Overrides the base URL path to proxy to.

=item plack.proxy.method

Overrides the request method (GET/POST etc.)

=item plack.proxy.headers

Overrides the request headers (as a hash reference)

=item plack.proxy.content

Overrides the request body (as a string).

=back

For example, the following builder code allows you to proxy all GET
requests to the lolcat image when UNIX epoch time can be multiplied by
12 (yes, i know it's a silly example) but proxies to the internal host
otherwise.

  my $mw = sub {
      my $app = shift;
      sub {
          my $env = shift;
          if ($env->{REQUEST_METHOD} eq 'GET' && time % 12 == 0) {
              $env->{'plack.proxy.url'} = 'http://lolcat.example.com/lol.png';
          }
          $app->($env);
      };
  };

  use Plack::Builder;

  builder {
      enable $mw;
      Plack::App::Proxy->new(host => 'http://10.0.0.1:8080')->to_app;
  };

=head1 AUTHOR
 
Lee Aylward

Masahiro Honma

Tatsuhiko Miyagawa

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 SEE ALSO

L<Plack::Builder>

=cut
