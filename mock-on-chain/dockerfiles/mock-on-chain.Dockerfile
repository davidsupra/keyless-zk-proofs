# syntax=docker/dockerfile:1.7

FROM archlinux:base-devel 
ARG TARGETARCH

COPY --link . .
EXPOSE 4444

RUN pacman -Syy && \
    pacman -S --noconfirm python

CMD ["./dockerfiles/mock-on-chain-run.sh"]
