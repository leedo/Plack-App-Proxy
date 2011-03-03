package Plack::App::Proxy::Backend::LWP;

use strict;
use parent 'Plack::App::Proxy::Backend';
use LWP::UserAgent;

sub call {
    my $self = shift;
    my ($env) = @_;

    my $req = HTTP::Request->new(
        $self->method => $self->url,
        HTTP::Headers->new(%{ $self->headers }),
        $self->content
    );
    my $ua = LWP::UserAgent->new;
    my $res = $ua->simple_request($req);
    # Just assume HTTP::Headers is a blessed hash ref
    my $headers = +{%{$res->headers}};

    $env->{'plack.proxy.last_protocol'} = '1.1'; # meh
    $env->{'plack.proxy.last_status'}   = $res->code;
    $env->{'plack.proxy.last_reason'}   = $res->message;
    $env->{'plack.proxy.last_url'}      = $self->url;

    return sub {
        my $cb = shift;
        $cb->([
            $res->code,
            [$self->response_headers->($headers)],
            [$res->content],
        ]);
    };
}

1;
