package Plack::App::Proxy::Backend;

use strict;
use parent 'Plack::Component';
use Plack::Util::Accessor qw/url req headers method content response_headers/;

1;
