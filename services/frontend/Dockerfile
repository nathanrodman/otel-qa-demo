# Debian-based (glibc) image: OTel operator Node.js auto-instrumentation works on it out of the box.
FROM node:22-slim
WORKDIR /app
COPY server.js .
ENV PORT=8080
EXPOSE 8080
USER node
CMD ["node", "server.js"]
