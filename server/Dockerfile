# Stage 1: Dependencies & Build
FROM node:20-alpine AS builder

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

# Stage 2: Production Runtime
FROM node:20-alpine

# Install dumb-init for PID 1 signal management (SIGTERM / SIGINT graceful handling)
RUN apk add --no-cache dumb-init

WORKDIR /app

# Copy production dependencies and application code
COPY --from=builder /app/node_modules ./node_modules
COPY . .

# Security best practice: run as non-root user
USER node

EXPOSE 3005

ENV NODE_ENV=production
ENV PORT=3005

HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget --no-verbose --tries=1 --spider http://localhost:3005/ || exit 1

ENTRYPOINT ["/usr/bin/dumb-init", "--"]
CMD ["node", "index.js"]
