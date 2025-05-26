FROM node:24-alpine

WORKDIR /app

# Copy package files
COPY package.json .

# Install dependencies
RUN npm install --production

# Copy application files
COPY app.js .

# Expose API port
EXPOSE 3001

# Start the API server
CMD ["node", "app.js"]