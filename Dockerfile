# syntax=docker/dockerfile:1.7
ARG BUN_VERSION=1-alpine

FROM mirror.gcr.io/library/node:22-alpine AS builder
# bun replaces oven/bun:* builder image. Pulling node from public.ecr.aws
# (no rate limit) and installing bun keeps build reproducible without
# touching docker.io.
RUN npm install -g bun@1.2.17
RUN apk add --no-cache libc6-compat openssl
WORKDIR /app
COPY . .

# NEXT_PUBLIC_* vars must be available as ENV during `bun run build` so
# Next.js statically inlines them into the client bundle. Without this,
# the bundle ships with the 'your-api-key-here' fallback and triggers
# "OpenWeatherMap API key is not configured" at runtime, regardless of
# what the runtime SOPS secret holds.
ARG NEXT_PUBLIC_OPENWEATHER_API_KEY
ARG NEXT_PUBLIC_MAPTILER_API_KEY
ARG NEXT_PUBLIC_ANALYTICS_API_KEY
ARG NEXT_PUBLIC_ANALYTICS_ENDPOINT
ARG NEXT_PUBLIC_ANALYTICS_ENABLED
ARG NEXT_PUBLIC_BETTER_AUTH_URL
ARG NEXT_PUBLIC_BETTER_STACK_SOURCE_TOKEN
ARG NEXT_PUBLIC_UMAMI_URL
ARG NEXT_PUBLIC_UMAMI_WEBSITE_ID
ARG NEXT_PUBLIC_CACHE_DURATION
ARG NEXT_PUBLIC_RATE_LIMIT

ENV NEXT_TELEMETRY_DISABLED=1 \
    NEXT_PUBLIC_OPENWEATHER_API_KEY=${NEXT_PUBLIC_OPENWEATHER_API_KEY} \
    NEXT_PUBLIC_MAPTILER_API_KEY=${NEXT_PUBLIC_MAPTILER_API_KEY} \
    NEXT_PUBLIC_ANALYTICS_API_KEY=${NEXT_PUBLIC_ANALYTICS_API_KEY} \
    NEXT_PUBLIC_ANALYTICS_ENDPOINT=${NEXT_PUBLIC_ANALYTICS_ENDPOINT} \
    NEXT_PUBLIC_ANALYTICS_ENABLED=${NEXT_PUBLIC_ANALYTICS_ENABLED} \
    NEXT_PUBLIC_BETTER_AUTH_URL=${NEXT_PUBLIC_BETTER_AUTH_URL} \
    NEXT_PUBLIC_BETTER_STACK_SOURCE_TOKEN=${NEXT_PUBLIC_BETTER_STACK_SOURCE_TOKEN} \
    NEXT_PUBLIC_UMAMI_URL=${NEXT_PUBLIC_UMAMI_URL} \
    NEXT_PUBLIC_UMAMI_WEBSITE_ID=${NEXT_PUBLIC_UMAMI_WEBSITE_ID} \
    NEXT_PUBLIC_CACHE_DURATION=${NEXT_PUBLIC_CACHE_DURATION} \
    NEXT_PUBLIC_RATE_LIMIT=${NEXT_PUBLIC_RATE_LIMIT}

RUN bun install --frozen-lockfile

RUN bun run build
RUN mkdir -p /app/public

FROM mirror.gcr.io/library/node:22-alpine AS runner
WORKDIR /app
ENV NODE_ENV=production \
    NEXT_TELEMETRY_DISABLED=1 \
    PORT=3000 \
    HOSTNAME=0.0.0.0

RUN apk add --no-cache libc6-compat openssl wget
RUN addgroup -g 1001 -S nodejs && adduser -u 1001 -S nextjs -G nodejs

COPY --from=builder --chown=nextjs:nodejs /app/.next/standalone ./
COPY --from=builder --chown=nextjs:nodejs /app/.next/static ./.next/static
COPY --from=builder --chown=nextjs:nodejs /app/public ./public

USER nextjs
EXPOSE 3000

HEALTHCHECK --interval=30s --timeout=10s --start-period=45s --retries=5 \
  CMD wget -O- http://localhost:3000/api/health 2>&1 || exit 1

CMD ["node", "server.js"]
