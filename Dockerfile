FROM n8nio/n8n:latest
USER root
RUN npm install --location=global cheerio marked \
 && echo 'NODE_PATH=/usr/local/lib/node_modules' >> /etc/environment
USER node
