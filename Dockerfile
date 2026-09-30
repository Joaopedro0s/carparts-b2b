# Imagem da API carparts-api
# Construída UMA vez pelo Jenkins (tag = número do build) e promovida
# de homologação para produção sem recompilar.

FROM node:22-alpine AS deps
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev && npm cache clean --force

FROM node:22-alpine
ENV NODE_ENV=production PORT=3000
WORKDIR /app
COPY --from=deps /app/node_modules ./node_modules
COPY package.json ./
COPY src ./src

# Metadados de rastreabilidade (qual commit está rodando)
ARG APP_VERSION=dev
ARG GIT_COMMIT=local
ENV APP_VERSION=${APP_VERSION} GIT_COMMIT=${GIT_COMMIT}
LABEL org.opencontainers.image.title="carparts-api" \
      org.opencontainers.image.version="${APP_VERSION}" \
      org.opencontainers.image.revision="${GIT_COMMIT}"

USER node
EXPOSE 3000
HEALTHCHECK --interval=30s --timeout=3s --retries=3 \
  CMD wget -qO- http://127.0.0.1:3000/health || exit 1
CMD ["node", "src/server.js"]
