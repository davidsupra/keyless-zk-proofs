# syntax=docker/dockerfile:1.7

FROM archlinux:base-devel 
ARG TARGETARCH

COPY --link . .
EXPOSE 4444

CMD ["./dockerfiles/mock-on-chain-run.sh"]
