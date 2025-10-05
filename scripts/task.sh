#!/bin/bash

set -e

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
REPO_ROOT=$(cd "$SCRIPT_DIR/.." && pwd)

install_deps() {
  if ! command -v python3 > /dev/null || ! command -v curl > /dev/null; then
    OS=$(uname -s)
    case $OS in
      Linux*)
        if command -v apt-get > /dev/null; then
          if command -v sudo > /dev/null; then
            sudo apt-get update
            sudo apt-get install -y python3 python3-pip pipx curl
          else
            apt-get update
            apt-get install -y python3 python3-pip pipx curl
          fi
        elif command -v pacman > /dev/null; then
          if command -v sudo > /dev/null; then
            sudo pacman -Syu --noconfirm
            sudo pacman -S --needed --noconfirm python python-pip python-pipx curl
            pipx install invoke
          else
            pacman -Syu --noconfirm
            pacman -S --needed --noconfirm python python-pip python-pipx curl
          fi
        else
          >&2 echo "No suitable package manager found for Linux."
        fi
        ;;
      Darwin*)
        if command -v brew > /dev/null; then
          brew install python
        else
          >&2 echo "Homebrew is not installed. Install Homebrew to use this."
        fi
        ;;
      *)
        >&2 echo "Unsupported OS: $OS"
        ;;
    esac
    >&2 echo "Dependencies installation finished."
  fi
}

install_deps

if ! command -v poetry > /dev/null; then
  >&2 echo "Poetry is required but was not found. Install Poetry from https://python-poetry.org/docs/#installation."
  exit 1
fi

poetry --directory "$REPO_ROOT" install
poetry --directory "$REPO_ROOT" run python "$SCRIPT_DIR/python/main.py" "$@"


