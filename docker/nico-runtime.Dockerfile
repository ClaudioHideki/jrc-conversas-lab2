FROM node:24.13.0-bookworm-slim

ARG GIT_SHA
LABEL org.opencontainers.image.revision=$GIT_SHA

WORKDIR /app/services/nico-runtime

COPY services/nico-runtime/package*.json ./
RUN npm ci --include=dev

COPY services/nico-runtime ./
RUN npm run build && npm prune --omit=dev
RUN printf '%s' "$GIT_SHA" | grep -Eq '^[0-9a-f]{40}$' \
  && printf '%s\n' "$GIT_SHA" > /app/.git_sha

ENV NODE_ENV=production
ENV PORT=3108

EXPOSE 3108

CMD ["npm", "start"]
