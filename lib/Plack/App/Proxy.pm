package Plack::App::Proxy;

use strict;
use parent 'Plack::Component';
use Plack::Util::Accessor qw/host url preserve_host_header/;
use Try::Tiny;

our $VERSION = '0.01';

sub call {
  my ($self, $env) = @_;
  $self->setup($env) unless $self->{proxy};
  
  my $url;
  if (ref $self->url eq 'CODE') {
    $url = $self->url->($env);
    return $url if ref $url eq "ARRAY";
  }
  elsif (ref $self->host eq 'CODE') {
    $url = $self->host->($env);
    return $url if ref $url eq "ARRAY";
    $url = $url . $env->{PATH_INFO};
  }
  else {
    $url = $self->host . $env->{PATH_INFO};
  }
  
  my @headers = ("X-Forwarded-For", $env->{REMOTE_ADDR});
  if ($self->preserve_host_header and $env->{HTTP_HOST}) {
    push @headers, "Host", $env->{HTTP_HOST};
  }
  
  # borrowed from FCGIDispatcher
  my $input = delete $env->{'psgi.input'};
  my $content = do { local $/; <$input> };
  
  return $self->{proxy}->($env->{REQUEST_METHOD}, $url, \@headers, $content);
}

sub setup {
  my ($self, $env) = @_;
  try {
    die "Falling back to blocking client" unless $env->{"psgi.streaming"};
    require AnyEvent::HTTP;
    $self->{proxy} = sub {$self->async(@_)};
  } catch {
    require LWP::UserAgent;
    $self->{proxy} = sub {$self->blocking(@_)};
    $self->{ua} = LWP::UserAgent->new;
  }
}

sub async {
  my ($self, $method, $url, $headers, $content) = @_;
  return sub {
    my $respond = shift;
    AnyEvent::HTTP::http_request(
      $method => $url,
      headers => {@$headers},
      body => $content,
      want_body_handle => 1,
      on_body => sub {
        my ($handle, $headers) = @_;
        if (!$handle or $headers->{Status} =~ /^59\d+/) {
          $respond->([502, ["Content-Type","text/html"], ["Gateway error"]]);
        }
        else {
          my $writer = $respond->([$headers->{Status},
                                  [$self->response_headers($headers)]]);
          $handle->on_eof(sub {
            undef $handle;
            $writer->close;
          });
          $handle->on_error(sub{});
          $handle->on_read(sub {
            my $data = $_[0]->rbuf;
            $writer->write($data) if $data;
          });
        }
      }
    );
  }
}

sub blocking {
  my ($self, $method, $url, $headers, $content) = @_;
  my $req = HTTP::Request->new($method => $url, $headers, $content);
  my $res = $self->{ua}->request($req);
  if ($res->code =~ /^5\d+/) {
    return [502, ["Content-Type","text/html"], ["Gateway error"]];
  }
  return [$res->code, [$self->response_headers($res)], [$res->content]];
}

sub response_headers {
  my ($self, $headers) = @_;
  my @valid_headers = qw/Content-Length Content-Type ETag
                      Last-Modified Cache-Control Expires/;
  if (ref $headers eq "HASH") {
    map {$_ => $headers->{lc $_}}
    grep {$headers->{lc $_}} @valid_headers; 
  }
  elsif (ref $headers eq "HTTP::Response") {
    map {$_ => $headers->header($_)}
    grep {$headers->header($_)} @valid_headers;
  }
}

1;

__END__
 
=head1 NAME
 
Plack::App::Proxy - proxy requests
 
=head1 SYNOPSIS
 
  use Plack::Builder;
 
  builder {
      # proxy all requests to 127.0.0.1:80
      mount "/static" => Plack::App::Proxy->new(host => "127.0.0.1:80")->to_app;
      
      # use some logic to decide which host to proxy to
      mount "/host" => Plack::App::Proxy->new(host => sub {
        my $env = shift;
        ...
        return $host;
      })->to_app;
      
      # use some logic to decide what url to proxy
      mounst "/url" => Plack::App::Proxy->new(url => sub {
        my $env => shift;
        ...
        return $url;
      })->to_app;
  };

=head1 DESCRIPTION
 
Plack::App::Proxy
 
=head1 AUTHOR
 
Lee Aylward
 
=head1 LICENSE
 
This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.
 
=head1 SEE ALSO
 
L<Plack::Builder>
 
=cut