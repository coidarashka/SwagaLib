# Сборка (твой оригинал)
FROM --platform=$TARGETPLATFORM rust:alpine AS build
ARG TELEMT_REPO=https://github.com/telemt/telemt.git
ARG TELEMT_REF=main
RUN apk add --no-cache ca-certificates git build-base musl-dev pkgconf perl binutils openssl-dev openssl-libs-static zlib-dev zlib-static && update-ca-certificates
WORKDIR /src
RUN git clone --depth=1 --branch "${TELEMT_REF}" "${TELEMT_REPO}" .
RUN cargo build --release --locked --bin telemt && \
    mkdir -p /out && install -Dm755 target/release/telemt /out/telemt && strip /out/telemt

# Рантайм
FROM alpine:latest AS runtime
RUN apk add --no-cache ca-certificates xxd
COPY --from=build /out/telemt /usr/local/bin/telemt

WORKDIR /app
# Скрипт, который создаёт конфиг и запускает прокси
RUN cat <<'EOF' > /app/start.sh
#!/bin/sh
SECRET=$(head -c 16 /dev/urandom | xxd -p)
DOMAIN="google.com"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"

echo "----------------------------------------------------------"
echo "👉 ТВОЙ СЕКРЕТ: $FULL_SECRET"
echo "👉 Чтобы прокси не спал, открой ссылку в браузере: https://ТВОЙ-ДОМЕН.koyeb.app"
echo "----------------------------------------------------------"

cat <<TOML > /app/telemt.toml
[general]
fast_mode = true
[general.modes]
tls = true
[server]
port = 443
listen_addr_ipv4 = "0.0.0.0"
[censorship]
tls_domain = "$DOMAIN"
[access.users]
admin = "$SECRET"
[[upstreams]]
type = "direct"
enabled = true
TOML

# Запускаем прокси на 443 и "пустышку" на 8000
# (чтобы Koyeb видел живой HTTP порт)
exec /usr/local/bin/telemt /app/telemt.toml &
nc -lk -p 8000 -e echo -e "HTTP/1.1 200 OK\n\nProxy is running!"
EOF

RUN chmod +x /app/start.sh
EXPOSE 443/tcp
EXPOSE 8000/http
ENTRYPOINT ["/app/start.sh"]
