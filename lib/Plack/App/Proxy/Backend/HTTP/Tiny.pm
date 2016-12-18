package Plack::App::Proxy::Backend::HTTP::Tiny;

use strict;
use parent 'Plack::App::Proxy::Backend';
use HTTP::Headers;

sub call {
    my ($self, $env) = @_;

    return sub {
        my ($respond) = @_;

        my $ua = Plack::App::Proxy::Backend::HTTP::Tiny::PreserveHeaders->new(
            max_redirect => 0,
            %{ $self->options || {} }
        );

        my $writer;

        my $res = $ua->request(
            $self->method => $self->url, {
                headers => $self->headers,
                content => $self->content,
                data_callback => sub {
                    my ($data, $res) = @_;

                    return if $res->{status} =~ /^59\d+/;

                    if (not $writer) {
                        $env->{'plack.proxy.last_protocol'} = '1.1'; # meh
                        $env->{'plack.proxy.last_status'}   = $res->{status};
                        $env->{'plack.proxy.last_reason'}   = $res->{reason};
                        $env->{'plack.proxy.last_url'}      = $self->url;

                        $writer = $respond->([
                            $res->{status},
                            [$self->response_headers->(HTTP::Headers->new(%{$res->{headers}}))],
                        ]);
                    }

                    $writer->write($data);
                },
            }
        );

        if ($writer) {
            $writer->close;
            return;
        }

        if ($res->{status} =~ /^59\d/) {
            return $respond->([502, ['Content-Type' => 'text/html'], ["Gateway error: $res->{content}"]]);
        }

        return $respond->([
            $res->{status},
            [$self->response_headers->(HTTP::Headers->new(%{$res->{headers}}))],
            [$res->{content}],
        ]);
    };
}

package Plack::App::Proxy::Backend::HTTP::Tiny::PreserveHeaders;

use parent 'HTTP::Tiny';

# Preserve Host and User-Agent headers
sub _prepare_headers_and_cb {
    my ($self, $request, $args, $url, $auth) = @_;

    my ($host, $user_agent);

    while (my ($k, $v) = each %{$args->{headers}}) {
        $host = $v if lc $k eq 'host';
        $user_agent = $v if lc $k eq 'user-agent';
    }

    $self->SUPER::_prepare_headers_and_cb($request, $args, $url, $auth);

    $request->{headers}{'host'} = $host if $host;
    delete $request->{headers}{'user-agent'} if not defined $user_agent;

    return;
}

1;

__END__

=head1 NAME

Plack::App::Proxy::Backend::HTTP::Tiny - backend which uses HTTP::Tiny

=head1 SYNOPSIS

  my $app = Plack::App::Proxy->new(backend => 'HTTP::Tiny')->to_app;

=head1 DESCRIPTION

This backend uses L<HTTP::Tiny> to make HTTP requests. This is the default
backend used when no backend is specified in the constructor.

=head1 AUTHOR

Piotr Roszatycki

Lee Aylward

Masahiro Honma

Tatsuhiko Miyagawa

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
