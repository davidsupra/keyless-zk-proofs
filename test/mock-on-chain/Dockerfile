# syntax=docker/dockerfile:1.7

FROM archlinux:base-devel as build_prover_service
ARG TARGETARCH

run pacman -Syu --noconfirm \
 && pacman -S --noconfirm rustup clang meson cmake make libyaml nasm gmp openssl curl git \
 && rustup default stable

COPY --link . .
COPY --link ./rust-rapidsnark/rapidsnark/build/subprojects/oneTBB-2022.0.0 ./rapidsnark-libdir


EXPOSE 4444

ENV LD_LIBRARY_PATH="./rapidsnark-libdir"
CMD ["./test/mock-on-chain/run.sh"]
