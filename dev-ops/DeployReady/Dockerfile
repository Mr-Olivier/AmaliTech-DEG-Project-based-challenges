FROM node:20-alpine

WORKDIR /app

# copy manifest first so the npm install layer is cached independently of source changes
COPY app/package*.json ./
RUN npm ci --only=production

COPY app/ .

# wget is needed for the docker-compose healthcheck
RUN apk add --no-cache wget

RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

ENV PORT=3000
EXPOSE $PORT

CMD ["node", "index.js"]
