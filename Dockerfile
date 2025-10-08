# Dockerfile — Alpine image with nginx + pocketbase (single container)
FROM alpine:3.18

# Install required packages
RUN apk add --no-cache nginx bash ca-certificates tar

# Create directories (include /data for the persistent volume)
RUN mkdir -p /var/log/nginx /run/nginx /app/release /data/release && \
    chown -R root:root /app /data

WORKDIR /app/release

COPY release/ /app/release/

RUN if [ -f /app/release/pocketbase/pocketbase ]; then chmod +x /app/release/pocketbase/pocketbase || true; fi

COPY nginx.conf /etc/nginx/nginx.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]

