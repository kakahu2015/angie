#!/usr/bin/perl

# (C) Maxim Dounin
# (C) 2023 Web Server LLC

# Tests for http proxy module, proxy_intercept_errors directive.

###############################################################################

use warnings;
use strict;

use Test::More;

BEGIN { use FindBin; chdir($FindBin::Bin); }

use lib 'lib';
use Test::Nginx;

###############################################################################

select STDERR; $| = 1;
select STDOUT; $| = 1;

my $t = Test::Nginx->new()->has(qw/http proxy rewrite http_v3/)
	->has_daemon("openssl")->plan(4);

$t->prepare_ssl();

$t->write_file_expand('nginx.conf', <<'EOF');

%%TEST_GLOBALS%%

daemon off;

events {
}

http {
    %%TEST_GLOBALS_HTTP%%

    server {
        listen       127.0.0.1:8080;
        server_name  localhost;

        location / {
            proxy_pass https://127.0.0.1:%%PORT_8999_UDP%%;
            proxy_http_version  3;
            proxy_intercept_errors on;
            error_page 401 500 /intercepted;
        }

        location = /intercepted {
            return 200 "intercepted\n";
        }
    }

    server {
        ssl_certificate     localhost.crt;
        ssl_certificate_key localhost.key;

        listen       127.0.0.1:%%PORT_8999_UDP%% quic;
        server_name  localhost;

        location / {
            return 404 "SEE-THIS";
        }

        location /500 {
            return 500;
        }

        location /auth {
            add_header WWW-Authenticate foo always;
            return 401;
        }

        location /auth-multi {
            add_header WWW-Authenticate foo always;
            add_header WWW-Authenticate bar always;
            return 401;
        }
    }
}

EOF

$t->run();

###############################################################################

# make sure errors without error_page set are not intercepted

like(http_get('/'), qr/SEE-THIS/, 'not intercepted');

# make sure errors with error_page are intercepted

like(http_get('/500'), qr/500.*intercepted/s, 'intercepted 500');
like(http_get('/auth'), qr/401.*www-authenticate.*intercepted/s,
	'intercepted 401');

# make sure multiple WWW-Authenticate headers are returned
# along with intercepted response (ticket #485)

TODO: {
local $TODO = 'not yet' unless $t->has_version('1.23.0');

like(http_get('/auth-multi'), qr/401.*www-authenticate: foo.*bar.*intercept/s,
	'intercepted 401 multi');

}

###############################################################################
