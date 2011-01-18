package Plack::App::Proxy;

use strict;
use parent 'Plack::Component';
use Plack::Util::Accessor qw/remote preserve_host_header/;
use Plack::Request;
use HTTP::Headers;
use Try::Tiny;
use AnyEvent::HTTP;

our $VERSION = '0.16';

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

    my $url = $env->{'plack.proxy.remote'} || $self->remote
        or return;

    # avoid double slashes
    $url =~ s!/$!! unless $env->{SCRIPT_NAME} && $env->{SCRIPT_NAME} =~ m!/$!;

    $url .= $env->{PATH_INFO} || '';
    $url .= '?' . $env->{QUERY_STRING} if defined $env->{QUERY_STRING} && length $env->{QUERY_STRING} > 0;

    return $url;
}

sub build_headers_from_env {
    my($self, $env, $req) = @_;

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

    my $url = $self->build_url_from_env($env)
        or return [502, ["Content-Type","text/html"], ["Can't determine proxy remote URL"]];

    # TODO: make sure Plack::Request recalculates psgi.input when it's reset
    my $req = Plack::Request->new($env);
    my $headers = $self->build_headers_from_env($env, $req);

    my $method  = $env->{REQUEST_METHOD};
    my $content = $req->content;

    return sub {
        my $respond = shift;
        my $cv = AE::cv;
        my $writer;
        AnyEvent::HTTP::http_request(
            $method => $url,
            headers => $headers,
            body => $content,
            recurse => 0,  # want not to treat any redirections
            on_header => sub {
                my $headers = shift;

                if ($headers->{Status} !~ /^59\d+/) {
                    $env->{'plack.proxy.last_protocol'} = $headers->{HTTPVersion};
                    $env->{'plack.proxy.last_status'}   = $headers->{Status};
                    $env->{'plack.proxy.last_reason'}   = $headers->{Reason};
                    $env->{'plack.proxy.last_url'}      = $headers->{URL};

                    $writer = $respond->([
                        $headers->{Status},
                        [$self->response_headers($headers)],
                    ]);
                }
                return 1;
            },
            on_body => sub {
              $writer->write($_[0]);
              return 1;
            },
            sub {
                my (undef, $headers) = @_;

                if (!$writer and $headers->{Status} =~ /^59\d/) {
                    $respond->([502, ["Content-Type","text/html"], ["Gateway error"]]);
                }

                $writer->close if $writer;
                $cv->send;

                # http_request may not release $cb with perl 5.8.8
                # and AE::HTTP 1.44. So free $env manually.
                undef $env;

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
      mount "/static" => Plack::App::Proxy->new(remote => "http://127.0.0.1:80")->to_app;
  };

  # Call from other app
  my $proxy = Plack::App::Proxy->new->to_app;
  my $app = sub {
      my $env = shift;
      ...
      $env->{'plack.proxy.url'} = $url;
      $proxy->($env);
  };

=head1 DESCRIPTION

Plack::App::Proxy is a middleware-aware proxy application for Plack.

=head1 OPTIONS

=over 4

=item remote

  Plack::App::Proxy->new(remote => 'http://perl.org')->to_app;

Specifies the base remote URL to proxy requests to.

  builder {
      mount "/example",
          Plack::App::Proxy->new(remote => 'http://example.com/app/foo')->to_app;
  };

This proxies incoming requests for C</example/bar> proxied to
C<http://example.com/app/foo/bar>.

=item preserve_host_header

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

=item plack.proxy.remote

Overrides the base URL path to proxy to.

=back

For example, the following builder code allows you to proxy all GET
requests for .png paths to the lolcat image (yes, a silly example) but
proxies to the internal host otherwise.

  my $mw = sub {
      my $app = shift;
      sub {
          my $env = shift;
          if ($env->{REQUEST_METHOD} eq 'GET' && $env->{PATH_INFO} =~ /\.png$/) {
              $env->{'plack.proxy.url'} = 'http://lolcat.example.com/lol.png';
          }
          $app->($env);
      };
  };

  use Plack::Builder;

  builder {
      enable $mw;
      Plack::App::Proxy->new(remote => 'http://10.0.0.1:8080')->to_app;
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
