# syntax=docker/dockerfile:1.7
# СТАДИЯ 1: Сборка (на основе твоего Dockerfile (2).txt)
FROM --platform=$TARGETPLATFORM rust:alpine AS build

ARG TELEMT_REPO=https://github.com/telemt/telemt.git
ARG TELEMT_REF=main

RUN apk add --no-cache ca-certificates git build-base musl-dev pkgconf perl binutils openssl-dev openssl-libs-static zlib-dev zlib-static && update-ca-certificates

WORKDIR /src
RUN git clone --depth=1 --branch "${TELEMT_REF}" "${TELEMT_REPO}" .

# Сборка статического бинарника
RUN cargo build --release --locked --bin telemt && \
    mkdir -p /out && install -Dm755 target/release/telemt /out/telemt && strip /out/telemt

# СТАДИЯ 2: Рантайм
FROM alpine:latest AS runtime
# Устанавливаем xxd для секретов и netcat для заглушки порта 8000
RUN apk add --no-cache ca-certificates xxd

COPY --from=build /out/telemt /usr/local/bin/telemt

WORKDIR /app

# Скрипт автоматизации: генерация секрета, конфига и запуск двух портов
RUN cat <<'EOF' > /app/start.sh
#!/bin/sh
# 1. Генерируем секрет (32 hex)
SECRET=$(head -c 16 /dev/urandom | xxd -p)
DOMAIN="google.com"
DOMAIN_HEX=$(echo -n "$DOMAIN" | xxd -p | tr -d '\n')
FULL_SECRET="ee${SECRET}${DOMAIN_HEX}"

echo "----------------------------------------------------------"
echo "🚀 ПРОКСИ ЗАПУЩЕН!"
echo "👉 ТВОЙ СЕКРЕТ: $FULL_SECRET"
echo "👉 ВАЖНО: Открой ссылку своего сервиса в браузере, чтобы проснуться."
echo "----------------------------------------------------------"

# 2. Создаем конфиг telemt.toml
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
mask = true
[access.users]
admin = "$SECRET"
[[upstreams]]
type = "direct"
enabled = true
TOML

# 3. Запускаем прокси в фоне
/usr/local/bin/telemt /app/telemt.toml &

# 4. Запускаем заглушку на 8000 порту, чтобы Koyeb видел HTTP активность
# Используем простейший ответ на любой запрос
while true; do 
  echo -e "HTTP/1.1 200 OK\nContent-Type: text/plain\n\nProxy is active" | nc -llp 8000
done
EOF

RUN chmod +x /app/start.sh

# Исправленные инструкции EXPOSE
EXPOSE 443/tcp
EXPOSE 8000/tcp

ENTRYPOINT ["/app/start.sh"]
