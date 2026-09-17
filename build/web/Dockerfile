# Static host for the exported Mata Zancudos web build.
#
# The unprivileged nginx image runs as a non-root user on port 8080, which keeps
# the container safe to run anywhere. The only real requirement of a Godot web
# build is the MIME types, and those come from nginx.conf next to this file:
# WebAssembly is refused by browsers unless .wasm is served as application/wasm.
FROM nginxinc/nginx-unprivileged:1.27-alpine

COPY nginx.conf /etc/nginx/nginx.conf
COPY index.html /usr/share/nginx/html/
COPY index.js /usr/share/nginx/html/
COPY index.wasm /usr/share/nginx/html/
COPY index.pck /usr/share/nginx/html/
COPY index.png /usr/share/nginx/html/
COPY index.icon.png /usr/share/nginx/html/
COPY index.apple-touch-icon.png /usr/share/nginx/html/
COPY index.audio.worklet.js /usr/share/nginx/html/
COPY index.audio.position.worklet.js /usr/share/nginx/html/

# The image already declares USER nginx and the healthcheck below probes the
# game page itself, so a container that starts but cannot serve index.html is
# reported as unhealthy rather than silently "up".
HEALTHCHECK --interval=30s --timeout=3s --start-period=5s --retries=3 \
    CMD wget --quiet --spider http://127.0.0.1:8080/index.html || exit 1

EXPOSE 8080
