# Dockerfile — minimal Alpine with nginx + pocketbase (single image)
FROM alpine:3.18

RUN apk add --no-cache nginx bash ca-certificates

# Create dirs
RUN mkdir -p /var/log/nginx /run/nginx

WORKDIR /app/release

# Copy your release folder (must contain dist/ and pocketbase/pocketbase)
COPY release/ /app/release/

# Ensure pocketbase binary is executable
RUN chmod +x /app/release/pocketbase/pocketbase || true

# Copy nginx config & start script
COPY nginx.conf /etc/nginx/nginx.conf
COPY start.sh /start.sh
RUN chmod +x /start.sh

EXPOSE 8080

CMD ["/start.sh"]
