# Caddy with the CrowdSec bouncer compiled in.
FROM caddy:2-builder AS builder

# Plugin pinned by tag so rebuilds are reproducible. Bump it by hand, like
# the app majors: https://github.com/hslatman/caddy-crowdsec-bouncer/releases
RUN xcaddy build \
    --with github.com/hslatman/caddy-crowdsec-bouncer/http@v0.14.1

FROM caddy:2

COPY --from=builder /usr/bin/caddy /usr/bin/caddy
