# ─── Stage 1: Install dependencies ──────────────────────────────────────────
FROM node:18-alpine AS deps

WORKDIR /app

# Copy only package files first (layer caching)
COPY app/package*.json ./

# Install only production dependencies
<<<<<<< HEAD
RUN npm ci --only=production && npm cache clean --force
=======
# Use npm install if no package-lock.json exists, otherwise npm ci
RUN if [ -f package-lock.json ]; then \
      npm ci --omit=dev && npm cache clean --force; \
    else \
      npm install --omit=dev && npm cache clean --force; \
    fi
>>>>>>> c32cead7928f8f8812d9586996bdf79cd46c5503


# ─── Stage 2: Production image ───────────────────────────────────────────────
FROM node:18-alpine AS runner

# Install dumb-init for proper signal handling
RUN apk add --no-cache dumb-init

# Create non-root user and group
RUN addgroup -S appgroup && adduser -S appuser -G appgroup

WORKDIR /app

# Copy production node_modules from deps stage
COPY --from=deps /app/node_modules ./node_modules

# Copy application source
COPY app/app.js .
COPY app/package.json .

# Set ownership
RUN chown -R appuser:appgroup /app

# Switch to non-root user
USER appuser

# Expose app port
EXPOSE 3000

# Use dumb-init as PID 1 for proper signal forwarding
ENTRYPOINT ["dumb-init", "--"]

# Health check built into image
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s --retries=3 \
  CMD wget -qO- http://localhost:3000/healthz || exit 1

CMD ["node", "app.js"]
