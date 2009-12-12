package Plack::App::Proxy;

use parent 'Plack::Component';
use Plack::Util::Accessor qw/host/;
use AnyEvent::HTTP;
use LWP::UserAgent;
use lib;

sub call {
  my ($self, $env) = @_;
  $self->setup($env) unless $self->{proxy};
  return $self->{proxy}->($env);
}

sub setup {
  my ($self, $env) = @_;
  if ($env->{"psgi.streaming"}) {
    $self->{proxy} = sub {$self->async(@_)};    
  }
  else {
    $self->{proxy} = sub {$self->block(@_)};
    $self->{ua} = LWP::UserAgent->new;
  }
}

sub async {
  my ($self, $env) = @_;
  return sub {
    my $respond = shift;
    http_request($env->{REQUEST_METHOD} => $self->host . $env->{PATH_INFO},
      want_body_handle => 1,
      on_body => sub {
        my ($handle, $headers) = @_;
        if (!$handle or $headers->{Status} =~ /^59\d+/) {
          $respond->([500, [], ["server error"]]);
        }
        else {
          my $writer = $respond->([200, [_res_headers($headers)]]);
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
      },
    );
  }
}

sub block {
  my ($self, $env) = @_;
  my $ua = $self->{ua};
  my $req = HTTP::Request->new(
    $env->{REQUEST_METHOD} => $self->host . $env->{PATH_INFO}
  );
  my $res = $ua->request($req);
  return [$res->code, [_res_headers($res)], [$res->content]];
}

sub _res_headers {
  my $headers = shift;
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