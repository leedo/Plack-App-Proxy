package Plack::App::Proxy::Backend::LWP;

use strict;
use parent 'Plack::App::Proxy::Backend';
use LWP::UserAgent;

sub call {
    my $self = shift;
    my ($env) = @_;

    return sub {
        my $respond = shift;

        my $req = HTTP::Request->new(
            $self->method => $self->url,
            HTTP::Headers->new(%{ $self->headers }),
            $self->content
        );

        my $ua = LWP::UserAgent->new;
        my $writer;

        $ua->add_handler(
            response_header => sub {
                my ($res) = @_;
                # Just assume HTTP::Headers is a blessed hash ref
                my $headers = { %{ $res->headers } };

                $env->{'plack.proxy.last_protocol'} = '1.1'; # meh
                $env->{'plack.proxy.last_status'}   = $res->code;
                $env->{'plack.proxy.last_reason'}   = $res->message;
                $env->{'plack.proxy.last_url'}      = $self->url;

                $writer = $respond->([
                    $res->code,
                    [$self->response_headers->($headers)],
                ]);
            },
        );
        $ua->add_handler(
            response_data => sub {
                my (undef, undef, undef, $data) = @_;
                $writer->write($data);
                return 1;
            },
        );
        $ua->add_handler(
            response_done => sub {
                $writer->close if $writer;
            },
        );

        my $res = $ua->simple_request($req);
        return if $writer;
        $respond->([
            $res->code,
            # Just assume HTTP::Headers is a blessed hash ref
            [$self->response_headers->({ %{ $res->headers } })],
            [$res->content],
        ]);
    };
}

1;

__END__

=head1 NAME

Plack::App::Proxy::Backend::LWP - backend which uses LWP::UserAgent

=head1 SYNOPSIS

  my $app = Plack::App::Proxy->new(backend => 'LWP')->to_app;

=head1 DESCRIPTION

This backend uses L<LWP::UserAgent> to make HTTP requests.

=head1 AUTHOR
 
Lee Aylward

Masahiro Honma

Tatsuhiko Miyagawa

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
