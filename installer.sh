#!/bin/bash

set -u

# Define variables
APP_NAME="joydx"
DOWNLOAD_URL_PREFIX="https://github.com/joy-dx/joydx-releases/releases/latest/download/"
REMOTE_ICON_URL="https://joydx.com/icon-square.svg"
JOYDX_PLATFORM=""
JOYDX_ARCHITECTURE=""
DOWNLOAD_SUFFIX=""
DOWNLOAD_VARIANT=""
DOWNLOADER=""
USER_SHELL=""
SHELL_RC_FILE=""
SHELL_EXPORT_SNIPPET=""

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

# Function to display error and exit
abort() {
  echo "Error: $1" >&2
  exit 1
}

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

major_minor() {
  echo "${1%%.*}.$(
    x="${1#*.}"
    echo "${x%%.*}"
  )"
}

chomp() {
  printf "%s" "${1/"$'\n'"/}"
}

# Function to display error and exit
error_exit() {
  printf "${tty_red}Error${tty_reset}: %s\n" "$(chomp "$1")" >&2
  exit 1
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

download_file() {
  local url="$1"
  local output="$2"

  case "${DOWNLOADER}" in
  curl)
    curl -L "${url}" -o "${output}"
    ;;
  wget)
    wget "${url}" -O "${output}"
    ;;
  *)
    error_exit "No supported downloader configured."
    ;;
  esac
}

create_desktop_entry() {
  DESKTOP_FILE="${HOME}/.local/share/applications/${APP_NAME}.desktop"
  ICON_PATH="${HOME}/.local/share/icons/hicolor/scalable/apps/${APP_NAME}.svg"
  mkdir -p "$(dirname "${DESKTOP_FILE}")"
  mkdir -p "$(dirname "${ICON_PATH}")"

  cat > "${DESKTOP_FILE}" <<EOF
[Desktop Entry]
Type=Application
Version=1.0
Name=JoyDX
Comment=Supercharge your Developer Experience
Exec=${INSTALL_PATH}/${APP_NAME}
Icon=${APP_NAME}
Terminal=false
Categories=Development;
EOF

  # Make sure permissions are right
  chmod 644 "${DESKTOP_FILE}"
  if retry 3 curl -L "${REMOTE_ICON_URL}" -o "${ICON_PATH}"; then
    ohai "Icon Downloaded"
  else
    error_exit "Failed to download icon ${REMOTE_ICON_URL}"
  fi

  if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$(dirname "${DESKTOP_FILE}")" >/dev/null 2>&1 || true
  fi

  if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    gtk-update-icon-cache ~/.local/share/icons/hicolor >/dev/null 2>&1 || true
  fi

  ohai "Desktop entry created at ${DESKTOP_FILE}"
}

detect_shell() {
  local shell_name=""

  if [[ -n "${SHELL:-}" ]]; then
    shell_name="$(basename "${SHELL}")"
  fi

  case "${shell_name}" in
  bash)
    USER_SHELL="bash"
    SHELL_RC_FILE="${HOME}/.bashrc"
    SHELL_EXPORT_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'
    ;;
  zsh)
    USER_SHELL="zsh"
    SHELL_RC_FILE="${HOME}/.zshrc"
    SHELL_EXPORT_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'
    ;;
  fish)
    USER_SHELL="fish"
    SHELL_RC_FILE="${HOME}/.config/fish/config.fish"
    SHELL_EXPORT_SNIPPET='fish_add_path $HOME/.local/bin'
    ;;
  ksh)
    USER_SHELL="ksh"
    SHELL_RC_FILE="${HOME}/.kshrc"
    SHELL_EXPORT_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'
    ;;
  *)
    USER_SHELL="sh"
    SHELL_RC_FILE="${HOME}/.profile"
    SHELL_EXPORT_SNIPPET='export PATH="$HOME/.local/bin:$PATH"'
    ;;
  esac

  ohai "Detected shell: ${USER_SHELL}"
  ohai "Shell config file: ${SHELL_RC_FILE}"
}

ensure_local_bin_in_shell_config() {
  if [[ -z "${HOME:-}" ]]; then
    error_exit "HOME environment variable is not set. Cannot update shell configuration."
  fi

  detect_shell

  mkdir -p "${HOME}/.local/bin"
  mkdir -p "$(dirname "${SHELL_RC_FILE}")"
  touch "${SHELL_RC_FILE}"

  if grep -Fqs "${SHELL_EXPORT_SNIPPET}" "${SHELL_RC_FILE}"; then
    ohai "${HOME}/.local/bin already configured in ${SHELL_RC_FILE}"
  else
    {
      printf "\n"
      printf "# Added by %s installer\n" "${APP_NAME}"
      printf "%s\n" "${SHELL_EXPORT_SNIPPET}"
    } >> "${SHELL_RC_FILE}"
    ohai "Added ${HOME}/.local/bin to PATH in ${SHELL_RC_FILE}"
  fi

  export PATH="${HOME}/.local/bin:$PATH"
  ohai "Added ${HOME}/.local/bin to PATH for this session"
}

detect_os_and_arch() {
  OS=$(uname -s)
  ARCH=$(uname -m)

  ohai "Detected OS: ${OS}"
  ohai "Detected Architecture: ${ARCH}"

  case "${OS}" in
  Linux)
    JOYDX_PLATFORM="linux"
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
    JOYDX_PLATFORM="darwin"
    macos_version="$(major_minor "$(/usr/bin/sw_vers -productVersion)")"
    ohai "MacOS Version: ${macos_version}"
    ;;
  *)
    error_exit "Unsupported operating system: ${OS}"
    ;;
  esac

  # Determine architecture for download
  case "${ARCH}" in
  x86_64)
    JOYDX_ARCHITECTURE="amd64"
    ;;
  aarch64)
    JOYDX_ARCHITECTURE="arm64"
    ;;
  *)
    error_exit "Unsupported architecture: ${ARCH}"
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
    elif [[ -d "$HOME/bin" ]]; then
      INSTALL_PATH="$HOME/bin"
    else
      warn "No suitable binary lookup folder found. Creating ${HOME}/.local/bin and updating your shell configuration."
      ensure_local_bin_in_shell_config
      INSTALL_PATH="$HOME/.local/bin"
    fi
  else
    error_exit "HOME environment variable is not set. Cannot determine a suitable installation path."
  fi
  export PATH="$INSTALL_PATH:$PATH"
  ohai "Installation path: ${INSTALL_PATH}"
}

check_downloader() {
  if command -v curl >/dev/null 2>&1; then
    DOWNLOADER="curl"
  elif command -v wget >/dev/null 2>&1; then
    DOWNLOADER="wget"
  else
    error_exit "Either cURL or wget is required to download the application. Please install one of them."
  fi

  ohai "Using downloader: ${DOWNLOADER}"
}

detect_webkit_version() {
  check_pkgconfig_version() {
    if command -v pkg-config >/dev/null 2>&1; then
      if pkg-config --exists webkit2gtk-4.1; then
        return 0
      elif pkg-config --exists webkit2gtk-4.0; then
        return 1
      fi
    fi
    return 2
  }

  check_library_version() {
    local lib_paths
    lib_paths=$(find /usr/lib* /lib* -type f \( -name "libwebkit2gtk-4.1*.so*" -o -name "libwebkit2gtk-4.0*.so*" \) 2>/dev/null | sort -u)
    if echo "$lib_paths" | grep -q "libwebkit2gtk-4.1"; then
      return 0
    elif echo "$lib_paths" | grep -q "libwebkit2gtk-4.0"; then
      return 1
    fi
    return 2
  }

  if check_pkgconfig_version; then
    DOWNLOAD_VARIANT="-webkit241"
    return 0
  elif [[ $? -eq 1 ]]; then
    DOWNLOAD_VARIANT=""
    return 0
  fi

  if check_library_version; then
    DOWNLOAD_VARIANT="-webkit241"
    return 0
  elif [[ $? -eq 1 ]]; then
    DOWNLOAD_VARIANT=""
    return 0
  fi

  DOWNLOAD_VARIANT=""
  return 0
}

download_distribution() {
    DOWNLOAD_SUFFIX=".zip"

    case "${JOYDX_PLATFORM}" in
    linux)
      find_install_path
      detect_webkit_version
      FILENAME="${APP_NAME}-${JOYDX_PLATFORM}-${JOYDX_ARCHITECTURE}${DOWNLOAD_VARIANT}${DOWNLOAD_SUFFIX}"
      DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX}${FILENAME}"

      ohai "Downloading ${FILENAME} to ${INSTALL_PATH}..."
      if retry 3 download_file "${DOWNLOAD_URL}" "${INSTALL_PATH}/${APP_NAME}"; then
        chmod +x "${INSTALL_PATH}/${APP_NAME}"
        ohai "Installation complete. You can now run '${APP_NAME}' from your terminal."
        create_desktop_entry
        "${INSTALL_PATH}/${APP_NAME}" >/dev/null 2>&1 &
      else
        error_exit "Failed to download ${FILENAME} from ${DOWNLOAD_URL}"
      fi
      ;;
    darwin)
      FILENAME="${APP_NAME}-${JOYDX_PLATFORM}-${JOYDX_ARCHITECTURE}${DOWNLOAD_SUFFIX}"
      DOWNLOAD_URL="${DOWNLOAD_URL_PREFIX}${FILENAME}"
      ohai "Downloading ${DOWNLOAD_URL} to /tmp/${APP_NAME}.zip"
      if retry 3 download_file "${DOWNLOAD_URL}" "/tmp/${APP_NAME}.zip"; then
        if [ ! -f "/tmp/${APP_NAME}.zip" ]; then
          echo "Error: ZIP file not found at '/tmp/${APP_NAME}.zip'"
          exit 1
        fi
        unzip -qq -o "/tmp/${APP_NAME}.zip" -d "/tmp/${APP_NAME}-install"

        mkdir -p "${HOME}/Applications"
        cp -R /tmp/${APP_NAME}-install/${APP_NAME}.app "${HOME}"/Applications/${APP_NAME}.app

        open "${HOME}"/Applications/${APP_NAME}.app

        ohai "Installation to ${HOME}/Applications/${APP_NAME}.app complete"
      else
        error_exit "Failed to download ${FILENAME} from ${DOWNLOAD_URL}"
      fi
      ;;
    esac

}

main() {
  # Main script execution starts here
  detect_os_and_arch
  check_downloader
  download_distribution

  ohai "Script finished successfully!"
}

main