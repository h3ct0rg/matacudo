# Static host for the exported Mata Zancudos web build.
#
# The unprivileged nginx image runs as a non-root user on port 8080, which keeps
# the container safe to run anywhere. The only real requirement of a Godot web
# build is the MIME types, and those come from nginx.conf next to this file:
# WebAssembly is refused by browsers unless .wasm is served as application/wasm.
#
# The build renames the engine payload to include the version
# (index-1.0.6.js / .wasm / .pck). A new version means new URLs, so a browser
# cannot serve a cached copy of a previous release. Pass the version in:
#
#   VERSION=1.0.6 docker compose up -d --build
#
# Keep it in step with config/version in project.godot.
FROM nginxinc/nginx-unprivileged:1.27-alpine

ARG VERSION=1.0.5

COPY nginx.conf /etc/nginx/nginx.conf
COPY version-bump.sh /tmp/version-bump.sh
COPY index.html /usr/share/nginx/html/
COPY index.js /usr/share/nginx/html/
COPY index.wasm /usr/share/nginx/html/
COPY index.pck /usr/share/nginx/html/
COPY index.png /usr/share/nginx/html/
COPY index.icon.png /usr/share/nginx/html/
COPY index.apple-touch-icon.png /usr/share/nginx/html/
COPY index.audio.worklet.js /usr/share/nginx/html/
COPY index.audio.position.worklet.js /usr/share/nginx/html/

# Runs as root only for this step, because the web root belongs to the nginx
# user; afterwards the image goes back to the unprivileged user. The `test -f`
# calls make the build fail loudly if a COPY above was ever dropped, instead of
# producing an image that serves a broken page. The wasm is compressed here, at
# build time, and nginx serves that copy with gzip_static, so the 39 MB engine
# travels compressed without costing CPU per request.
USER root
RUN set -eu; \
    test -f /usr/share/nginx/html/index.wasm; \
    test -f /usr/share/nginx/html/index.pck; \
    sh /tmp/version-bump.sh "$VERSION" /usr/share/nginx/html; \
    gzip -9 -k "/usr/share/nginx/html/index-$VERSION.wasm"; \
    rm -f /usr/share/nginx/html/index.js /usr/share/nginx/html/index.pck /usr/share/nginx/html/index.wasm; \
    rm -f /tmp/version-bump.sh; \
    chown -R nginx:nginx /usr/share/nginx/html; \
    ls -la /usr/share/nginx/html
USER nginx

# The image already declares USER nginx and the healthcheck below probes the
# game page itself, so a container that starts but cannot serve index.html is
# reported as unhealthy rather than silently "up".
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --spider http://127.0.0.1:8080/index.html || exit 1

EXPOSE 8080
