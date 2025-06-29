FROM n8nio/n8n:latest
USER root
RUN npm install --location=global cheerio marked && \
    grep -q '^NODE_PATH=' /etc/environment && \
    sed -i 's|^NODE_PATH=.*|NODE_PATH=/usr/local/lib/node_modules|' /etc/environment || \
    echo 'NODE_PATH=/usr/local/lib/node_modules' >> /etc/environment
USER node
