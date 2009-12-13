package Plack::App::Proxy;

use strict;
use parent 'Plack::Component';
use Plack::Util::Accessor qw/host preserve_host_header/;

sub call {
  my ($self, $env) = @_;
  $self->setup($env) unless $self->{proxy};
  
  my $url;
  if (ref $self->host eq 'CODE') {
    $url = $self->host->($env);
    return $url if ref $url eq "ARRAY";
  }
  else {
    $url = $self->host . $env->{PATH_INFO};
  }
  
  my @headers = ("X-Forwarded-For", $env->{REMOTE_ADDR});
  if ($self->preserve_host_header and $env->{HTTP_HOST}) {
    push @headers, "Host", $env->{HTTP_HOST};
  }
  
  return $self->{proxy}->($env->{REQUEST_METHOD}, $url, @headers);
}

sub setup {
  my ($self, $env) = @_;
  if ($env->{"psgi.streaming"}) {
    require AnyEvent::HTTP;
    $self->{proxy} = sub {$self->async(@_)};
  }
  else {
    require LWP::UserAgent;
    $self->{proxy} = sub {$self->blocking(@_)};
    $self->{ua} = LWP::UserAgent->new;
  }
}

sub async {
  my ($self, $method, $url, @headers) = @_;
  return sub {
    my $respond = shift;
    AnyEvent::HTTP::http_request(
      $method => $url,
      headers => {@headers},
      want_body_handle => 1,
      on_body => sub {
        my ($handle, $headers) = @_;
        if (!$handle or $headers->{Status} =~ /^59\d+/) {
          $respond->([500, [], ["server error"]]);
        }
        else {
          my $writer = $respond->([$headers->{Status},
                                  [$self->_res_headers($headers)]]);
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
  my ($self, $method, $url, @headers) = @_;
  my $ua = $self->{ua};
  my $req = HTTP::Request->new($method => $url, [@headers]);
  my $res = $ua->request($req);
  return [$res->code, [$self->_res_headers($res)], [$res->content]];
}

sub _res_headers {
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