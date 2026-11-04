FROM node:24-alpine
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force
COPY certs certs
COPY src src
RUN mkdir /data && chown node:node /data
USER node
ENV NODE_ENV=production DATABASE_PATH=/data/textfix.db PORT=3000
EXPOSE 3000
CMD ["node", "--disable-warning=ExperimentalWarning", "src/server.ts"]
