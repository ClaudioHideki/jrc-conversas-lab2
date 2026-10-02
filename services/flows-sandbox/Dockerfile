FROM node:24.13.0-bookworm-slim
ARG GIT_SHA
LABEL org.opencontainers.image.revision=$GIT_SHA
WORKDIR /srv
COPY package*.json ./
RUN npm ci --omit=dev --ignore-scripts
COPY *.mjs ./
RUN printf '%s' "$GIT_SHA" | grep -Eq '^[0-9a-f]{40}$' \
  && printf '%s\n' "$GIT_SHA" > /srv/.git_sha
USER node
CMD ["node", "--max-old-space-size=128", "server.mjs"]
