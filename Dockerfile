FROM n8n/n8n:latest

# Set the user to root to install packages
USER root

# Install additional packages needed for various integrations
RUN apk add --no-cache \
    postgresql-client \
    curl \
    wget \
    git \
    python3 \
    py3-pip \
    build-base \
    python3-dev

# Create necessary directories
RUN mkdir -p /data/shared \
    && mkdir -p /home/node/.n8n \
    && mkdir -p /home/node/.n8n/custom

# Set proper permissions
RUN chown -R node:node /data \
    && chown -R node:node /home/node

# Switch back to the node user for security
USER node

# Set environment variables
ENV N8N_HOST=0.0.0.0
ENV N8N_PORT=5678
ENV N8N_PROTOCOL=http
ENV NODE_ENV=production
ENV N8N_LOG_LEVEL=info
ENV N8N_LOG_OUTPUT=console
ENV EXECUTIONS_DATA_PRUNE=true
ENV EXECUTIONS_DATA_MAX_AGE=168

# Expose the port
EXPOSE 5678

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=60s --retries=3 \
  CMD curl -f http://localhost:5678/healthz || exit 1

# Start n8n
CMD ["n8n", "start"]