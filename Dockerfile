# syntax=docker/dockerfile:1.7
# Сборка на основе твоего исходника 
FROM --platform=$TARGETPLATFORM rust:alpine AS build

ARG TELEMT_REPO=https://github.com/telemt/telemt.git
ARG TELEMT_REF=main

RUN apk add --no-cache ca-certificates git build-base musl-dev pkgconf perl binutils openssl-dev openssl-libs-static zlib-dev zlib-static && update-ca-certificates

WORKDIR /src
# Клонирование и сборка [cite: 2, 7]
RUN git clone --depth=1 --branch "${TELEMT_REF}" "${TELEMT_REPO}" .
RUN cargo build --release --locked --bin telemt && \
    mkdir -p /out && install -Dm755 target/release/telemt /out/telemt && strip /out/telemt

# Финальный образ (alpine вместо distroless, чтобы работал скрипт генерации ссылки)
FROM alpine:latest AS runtime
RUN apk add --no-cache ca-certificates xxd
COPY --from=build /out/telemt /usr/local/bin/telemt

WORKDIR /app
RUN adduser -D -u 1000 nonroot && chown -R nonroot:nonroot /app

# Скрипт автоматизации 
RUN cat <<'EOF' > /app/start.sh
#!/bin/sh
# Генерируем 32-hex секрет 
SECRET=$(head -c 16 /dev/urandom | xxd -p)
DOMAIN="google.com"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"

# Пытаемся определить хост платформы
HOST=${KOYEB_PUBLIC_DOMAIN:-${RENDER_EXTERNAL_HOSTNAME:-"your-host.com"}}
PORT="443"

echo "=========================================================="
echo "🚀 ПРОКСИ ЗАПУЩЕН!"
echo "🔗 Ссылка для Telegram:"
echo "tg://proxy?server=${HOST}&port=${PORT}&secret=${FULL_SECRET}"
echo "=========================================================="

# Генерируем telemt.toml 
cat <<TOML > /app/telemt.toml
[general]
prefer_ipv6 = false
fast_mode = true
[general.modes]
classic = false
secure = false
tls = true
[server]
port = 443
listen_addr_ipv4 = "0.0.0.0"
[censorship]
tls_domain = "$DOMAIN"
mask = true
[access.users]
admin = "$SECRET"
[[upstreams]]
type = "direct"
enabled = true
TOML

exec /usr/local/bin/telemt /app/telemt.toml
EOF

RUN chmod +x /app/start.sh
EXPOSE 443/tcp
USER 1000:1000
ENTRYPOINT ["/app/start.sh"]
