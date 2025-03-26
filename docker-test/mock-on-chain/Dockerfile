# syntax=docker/dockerfile:1.7

FROM archlinux:base-devel as build_prover_service
ARG TARGETARCH


COPY --link . .


EXPOSE 4444

ENV LD_LIBRARY_PATH="./rapidsnark-libdir"
CMD ["./test/mock-on-chain/run.sh"]
