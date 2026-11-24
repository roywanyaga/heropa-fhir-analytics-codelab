#!/usr/bin/env bash
#
# provision-heropa.sh prepares the headless Ubuntu VM behind the Heropa
# template for the FHIR Analytics codelab.
#
# It installs Docker Engine with the Compose plugin, then builds the workspace
# image and pulls the two other images the lab uses. The workspace image holds
# everything else, which is the JDK, the codelab checkout, a warm Gradle cache
# and the editor. Nothing else is installed on the VM itself, and Android
# Studio and the Android SDK are not needed. Every step is guarded, so a second
# run changes nothing.
#
# Run it from this folder on the VM with
#
#   sudo ./provision-heropa.sh
#
# Optional settings come from the environment.
#
#   LEARNER_USER   the account learners use, which is added to the docker
#                  group (defaults to the user who ran sudo)
#   SKIP_UPGRADE   set it to skip apt-get upgrade
#   SKIP_BUILD     set it to install Docker only and leave the images alone

set -euo pipefail
trap 'die "failed at line $LINENO while running $BASH_COMMAND"' ERR

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LEARNER_USER="${LEARNER_USER:-}"
export DEBIAN_FRONTEND=noninteractive

# Fresh images run unattended-upgrades soon after boot. Wait for its dpkg lock
# instead of failing on it.
APT=(apt-get -o DPkg::Lock::Timeout=600)

# The images lab-init.sh and docker-compose.yml use besides the workspace.
DOCKER_IMAGES=("nginx:1.27-alpine" "certbot/certbot:v5.10.0" "postgres:18" "hapiproject/hapi:v8.8.0-1" "us-docker.pkg.dev/cloud-build-fhir/fhir-analytics/main:latest")

CODENAME=""
REBOOT_REQUIRED=0

# --- helpers ----------------------------------------------------------------

log()  { printf '[%s] %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
warn() { printf '[%s] WARNING %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; }
die()  { printf '[%s] ERROR %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*" >&2; exit 1; }

pkg_installed() {
    dpkg-query -W -f='${Status}' "$1" 2>/dev/null | grep -q 'ok installed'
}

# Install only the packages that are missing, so re-runs stay quiet.
apt_install() {
    local missing=() pkg
    for pkg in "$@"; do
        pkg_installed "$pkg" || missing+=("$pkg")
    done
    [ "${#missing[@]}" -gt 0 ] || return 0
    log "installing ${missing[*]}"
    "${APT[@]}" install -y "${missing[@]}"
}

# --- 1. preflight -----------------------------------------------------------

preflight() {
    log "=== preflight ==="

    [ "$(id -u)" -eq 0 ] || die "must run as root, so try sudo $0"
    [ -r /etc/os-release ] || die "/etc/os-release is not readable, so this is probably not Ubuntu"

    # shellcheck disable=SC1091
    . /etc/os-release
    CODENAME="${UBUNTU_CODENAME:-${VERSION_CODENAME:-}}"
    [ -n "$CODENAME" ] || die "could not determine the Ubuntu codename"
    [ "$(dpkg --print-architecture)" = "amd64" ] \
        || die "the workspace image installs the amd64 build of code-server"
    log "detected ${PRETTY_NAME:-unknown} (codename $CODENAME)"

    [ -n "$LEARNER_USER" ] || LEARNER_USER="${SUDO_USER:-}"
    [ -n "$LEARNER_USER" ] && [ "$LEARNER_USER" != "root" ] \
        || die "no learner account resolved, so run it with sudo from that account or set LEARNER_USER"
    id "$LEARNER_USER" >/dev/null 2>&1 || die "user '$LEARNER_USER' does not exist"
    log "learner account is $LEARNER_USER"

    local mem_gb
    mem_gb=$(( $(awk '/MemTotal/ {print $2}' /proc/meminfo) / 1024 / 1024 ))
    [ "$mem_gb" -ge 7 ] \
        || warn "this VM has about ${mem_gb} GB of memory. Untested. HAPI, the pipeline and Postgres need about 6 GB together."

    log "updating the package index"
    "${APT[@]}" update

    if [ -n "${SKIP_UPGRADE:-}" ]; then
        log "SKIP_UPGRADE is set, so apt-get upgrade is skipped"
    else
        log "upgrading installed packages"
        "${APT[@]}" upgrade -y
    fi

    apt_install ca-certificates curl git openssl qrencode
}

# --- 2. docker --------------------------------------------------------------
# https://docs.docker.com/engine/install/ubuntu/#install-using-the-repository

install_docker() {
    log "=== docker ==="

    if ! pkg_installed docker-ce; then
        log "adding the Docker apt repository"
        install -m 0755 -d /etc/apt/keyrings
        curl -fsSL https://download.docker.com/linux/ubuntu/gpg \
            -o /etc/apt/keyrings/docker.asc
        chmod a+r /etc/apt/keyrings/docker.asc

        tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $CODENAME
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF

        "${APT[@]}" update
        apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        log "docker-ce is already installed"
    fi

    systemctl enable --now docker

    if id -nG "$LEARNER_USER" | tr ' ' '\n' | grep -qx docker; then
        log "user '$LEARNER_USER' is already in the docker group"
    else
        log "adding user '$LEARNER_USER' to the docker group"
        usermod -aG docker "$LEARNER_USER"
    fi
}

# --- 3. images --------------------------------------------------------------

build_images() {
    log "=== images ==="

    if [ -n "${SKIP_BUILD:-}" ]; then
        log "SKIP_BUILD is set, so no image is built or pulled"
        return 0
    fi

    local image
    for image in "${DOCKER_IMAGES[@]}"; do
        if docker image inspect "$image" >/dev/null 2>&1; then
            log "image $image is already pulled"
        else
            log "pulling $image"
            docker pull "$image"
        fi
    done

    # The build clones the codelab, downloads every dependency and compiles the
    # app twice, so the first run takes around ten minutes. Later runs come
    # from the layer cache.
    log "building the workspace image"
    docker build -t analytics-codelab-workspace:local "$SCRIPT_DIR/workspace"
}

# --- 4. summary -------------------------------------------------------------

summary() {
    [ -f /var/run/reboot-required ] && REBOOT_REQUIRED=1

    cat <<EOF

============================================================
 Provisioning complete
============================================================

  docker      $(docker --version 2>/dev/null || echo 'not reporting a version')
  compose     $(docker compose version --short 2>/dev/null || echo 'not reporting a version')
  workspace   $(docker image inspect -f '{{.Id}}' analytics-codelab-workspace:local 2>/dev/null | cut -c8-19 || echo 'not built')

Next steps

  1. Log out and back in as $LEARNER_USER, so the docker group takes
     effect. Check with docker run --rm hello-world

  2. Start the lab once to prove it works.

       ./lab-init.sh

  3. Before saving the template, remove what belongs to this one VM.

       ./lab-init.sh --clean
EOF

    if [ "$REBOOT_REQUIRED" -eq 1 ]; then
        cat <<'EOF'

  A reboot is pending after a kernel or libc upgrade. Reboot before
  saving the template.

       sudo reboot
EOF
    fi

    echo
}

# --- main -------------------------------------------------------------------

main() {
    preflight
    install_docker
    build_images
    summary
}

main "$@"
