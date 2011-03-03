package Plack::App::Proxy::Backend;

use strict;
use parent 'Plack::Component';
use Plack::Util::Accessor qw/url req headers method content response_headers/;

1;

__END__

=head1 NAME

Plack::App::Proxy::Backend - pluggable backend for making the actual HTTP request

=head1 SYNOPSIS

  package Plack::App::Proxy::Backend::foo;
  use parent 'Plack::App::Proxy::Backend';
  sub call {
      my $self = shift;
      my ($env) = @_;
      # ...
  }

=head1 DESCRIPTION

This is a base class for HTTP backends for L<Plack::App::Proxy>.

=head1 AUTHOR
 
Lee Aylward

Masahiro Honma

Tatsuhiko Miyagawa

=head1 LICENSE

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
