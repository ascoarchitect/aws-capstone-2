FROM nginx:alpine

# Install dependencies
RUN apk add --no-cache wget

# Create web directory
WORKDIR /usr/share/nginx/html

# Download js-dos files and Civilization game
RUN wget https://js-dos.com/6.22/current/js-dos.js && \
    wget https://js-dos.com/6.22/current/wdosbox.js && \
    wget https://js-dos.com/6.22/current/wdosbox.wasm.js && \
    wget -O civ-game.zip "https://archive.org/download/msdos_sid_meier_civilization/Civilizations.zip"

# Copy index.html
COPY index.html .

# Configure nginx to proxy API requests and health checks
RUN echo 'server { \
    listen 8000; \
    location / { \
        root /usr/share/nginx/html; \
        index index.html; \
    } \
    location /api/ { \
        proxy_pass http://stats-api-service:3001; \
        proxy_http_version 1.1; \
        proxy_set_header Upgrade $http_upgrade; \
        proxy_set_header Connection "upgrade"; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
    location /health { \
        proxy_pass http://stats-api-service:3001/health; \
        proxy_http_version 1.1; \
        proxy_set_header Host $host; \
        proxy_set_header X-Real-IP $remote_addr; \
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for; \
        proxy_set_header X-Forwarded-Proto $scheme; \
    } \
}' > /etc/nginx/conf.d/default.conf

EXPOSE 8000

CMD ["nginx", "-g", "daemon off;"]
