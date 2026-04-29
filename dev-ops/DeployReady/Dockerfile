FROM node:20-alpine

WORKDIR /app

# copy manifest first so npm install is cached separately from source code
COPY app/package*.json ./
RUN npm ci --only=production

COPY app/ .

# wget is used by docker-compose for the health check
RUN apk add --no-cache wget

# don't run the app as root
RUN addgroup -S appgroup && adduser -S appuser -G appgroup
USER appuser

ENV PORT=3000
EXPOSE $PORT

CMD ["node", "index.js"]
