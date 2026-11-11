# Single-stage Alpine; the xray binary is downloaded at runtime by
# entrypoint.sh (curl + unzip). Avoids the ghcr.io multi-stage COPY,
# which failed on Voroa's builder.
FROM alpine:3.20
RUN apk add --no-cache ca-certificates curl unzip
WORKDIR /app
COPY entrypoint.sh ./
RUN chmod +x entrypoint.sh

EXPOSE 8080
CMD ["sh", "./entrypoint.sh"]
