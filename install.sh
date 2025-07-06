#!/bin/bash

set -u

# Define variables
APP_NAME="joydx"
REPO_OWNER="joy-dx"
REPO_NAME="desktop"
LATEST_VERSION_URL="https://joydx.com/info/latest-version"

# Function to display error and exit
abort() {
  echo "Error: $1" >&2
  exit 1
}

# Fail fast with a concise message when not using bash
# Single brackets are needed here for POSIX compatibility
# shellcheck disable=SC2292
if [ -z "${BASH_VERSION:-}" ]
then
  abort "Bash is required to interpret this script."
fi
if [[ -t 1 ]]; then
  tty_escape() { printf "\033[%sm" "$1"; }
else
  tty_escape() { :; }
fi
tty_mkbold() { tty_escape "1;$1"; }
tty_blue="$(tty_mkbold 34)"
tty_red="$(tty_mkbold 31)"
tty_bold="$(tty_mkbold 39)"
tty_reset="$(tty_escape 0)"
shell_join() {
  local arg
  printf "%s" "$1"
  shift
  for arg in "$@"; do
    printf " "
    printf "%s" "${arg// /\ }"
  done
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

ohai() {
  printf "${tty_blue}==>${tty_bold} %s${tty_reset}\n" "$(shell_join "$@")"
}

warn() {
  printf "${tty_red}Warning${tty_reset}: %s\n" "$(chomp "$1")" >&2
}

retry() {
  local tries="$1" n="$1" pause=2
  shift
  if ! "$@"; then
    while [[ $((--n)) -gt 0 ]]; do
      warn "$(printf "Trying again in %d seconds: %s" "${pause}" "$(shell_join "$@")")"
      sleep "${pause}"
      ((pause *= 2))
      if "$@"; then
        return
      fi
    done
    error_exit "$(printf "Failed %d times doing: %s" "${tries}" "$(shell_join "$@")")"
  fi
}

detect_os_and_arch() {
  OS=$(uname -s)
  ARCH=$(uname -m)

  ohai "Detected OS: ${OS}"
  ohai "Detected Architecture: ${ARCH}"

  case "${OS}" in
  Linux)
    if [[ -f "/etc/os-release" ]]; then
      . /etc/os-release
      DISTRO=${ID}
      VERSION=${VERSION_ID}
      ohai "Detected Distribution: ${DISTRO}"
      ohai "Detected Version: ${VERSION}"
    else
      error_exit "Could not detect Linux distribution and version."
    fi
    ;;
  Darwin)
    ohai "Detected macOS"
    macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"
    ohai "macOS Version: ${macos_version}"
    ;;
  *)
    error_exit "Unsupported operating system: ${OS}"
    ;;
  esac
}

find_install_path() {
  INSTALL_PATH=""
  if [[ -n "$HOME" ]]; then
    if [[ ":$PATH:" == *":$HOME/.local/bin:"* ]]; then
      INSTALL_PATH="$HOME/.local/bin"
    elif [[ ":$PATH:" == *":$HOME/bin:"* ]]; then
      INSTALL_PATH="$HOME/bin"
    elif [[ -d "$HOME/.local/bin" ]]; then
      INSTALL_PATH="$HOME/.local/bin"
      warn "Adding $INSTALL_PATH to PATH for this session. You might want to add it permanently."
      export PATH="$INSTALL_PATH:$PATH"
    elif [[ -d "$HOME/bin" ]]; then
      INSTALL_PATH="$HOME/bin"
      warn "Adding $INSTALL_PATH to PATH for this session. You might want to add it permanently."
      export PATH="$INSTALL_PATH:$PATH"
    else
      error_exit "No suitable binary lookup folder found in your home directory (e.g., ~/.local/bin or ~/bin). Please create one and add it to your PATH."
    fi
  else
    error_exit "HOME environment variable is not set. Cannot determine a suitable installation path."
  fi
  ohai "Installation path: ${INSTALL_PATH}"
}

check_curl() {
  if ! command -v curl &>/dev/null; then
    error_exit "cURL is required to download the application. Please install it."
  fi
}

# Main script execution starts here
detect_os_and_arch
check_curl
find_install_path

ohai "Fetching latest version from ${LATEST_VERSION_URL}..."
LATEST_VERSION=$(retry 3 curl -s "${LATEST_VERSION_URL}")
if [ -z "${LATEST_VERSION}" ]; then
  error_exit "Failed to retrieve the latest version from ${LATEST_VERSION_URL}"
fi
ohai "Latest version available: ${LATEST_VERSION}"

# 5. Download and install
case "${OS}" in
Linux)
  # Determine architecture for download
  case "${ARCH}" in
  x86_64)
    DOWNLOAD_ARCH="x86-64"
    ;;
  aarch64)
    DOWNLOAD_ARCH="aarch64"
    ;;
  *)
    error_exit "Unsupported Linux architecture: ${ARCH}"
    ;;
  esac

  # Determine WebKit dependency string for download based on distribution
  # This is a simplification. A more robust solution might involve checking
  # specific library versions or using a more sophisticated detection method.
  WEBKIT_DOWNLOAD_SUFFIX=""
  if [[ "${DISTRO}" == "debian" || "${DISTRO}" == "ubuntu" ]]; then
    if version_ge "$VERSION" "22.04"; then
      WEBKIT_DOWNLOAD_SUFFIX="wk4-1"
    else
      WEBKIT_DOWNLOAD_SUFFIX="wk4-0"
    fi
  elif [[ "${DISTRO}" == "fedora" || "${DISTRO}" == "centos" || "${DISTRO}" == "rhel" || "${DISTRO}" == "almalinux" || "${DISTRO}" == "rocky" ]]; then
    WEBKIT_DOWNLOAD_SUFFIX="wk4-0"
  elif [[ "${DISTRO}" == "arch" ]]; then
    WEBKIT_DOWNLOAD_SUFFIX="wk4-1"
  else
    warn "Could not definitively determine WebKit suffix for distribution '${DISTRO}'. Defaulting to wk4-1."
    WEBKIT_DOWNLOAD_SUFFIX="wk4-1"
  fi

  FILENAME="${APP_NAME}-linux-${DOWNLOAD_ARCH}-${WEBKIT_DOWNLOAD_SUFFIX}-${LATEST_VERSION}"
  DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${LATEST_VERSION}/${FILENAME}"

  ohai "Downloading ${FILENAME} to ${INSTALL_PATH}..."
  if retry 3 curl -L "${DOWNLOAD_URL}" -o "${INSTALL_PATH}/${APP_NAME}"; then
    execute chmod +x "${INSTALL_PATH}/${APP_NAME}"
    ohai "Installation complete. You can now run '${APP_NAME}' from your terminal."
  else
    error_exit "Failed to download ${FILENAME} from ${DOWNLOAD_URL}"
  fi
  ;;
Darwin)
  case "${ARCH}" in
  x86_64)
    DOWNLOAD_ARCH="x86-64"
    ;;
  aarch64)
    DOWNLOAD_ARCH="aarch64"
    ;;
  *)
    error_exit "Unsupported macOS architecture: ${ARCH}"
    ;;
  esac

  # For macOS, the download filename is simpler
  FILENAME="${APP_NAME}-darwin-${DOWNLOAD_ARCH}-${LATEST_VERSION}.app"
  DOWNLOAD_URL="https://github.com/${REPO_OWNER}/${REPO_NAME}/releases/download/${LATEST_VERSION}/${FILENAME}"

  ohai "Downloading ${FILENAME}..."
  if retry 3 curl -L "${DOWNLOAD_URL}" -o "$HOME/Downloads/${FILENAME}"; then
    ohai "Download complete. To install, drag and drop '$HOME/Downloads/${FILENAME}' into your Applications folder."
    ohai "You can find your Applications folder in Finder, usually on the left sidebar."
  else
    error_exit "Failed to download ${FILENAME} from ${DOWNLOAD_URL}"
  fi
  ;;
esac

ohai "Script finished successfully!"