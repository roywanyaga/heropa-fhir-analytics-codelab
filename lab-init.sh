#!/usr/bin/env bash
#
# lab-init.sh starts the analytics lab on this VM and prints where to open it.
# A learner runs it after the lab launches, and again whenever the addresses
# are lost or stop working. Each run reads the VM's public IP again. With a
# permanent IP nothing has changed and it only prints the summary again. When
# the IP changed it gets a certificate for the new address. Either way its
# closing summary says what changed since the last run and what to do. The
# password and the learner's code are kept.
#
#   ./lab-init.sh            start the lab
#   ./lab-init.sh --reset    throw away the learner's changes (the ViewDefinitions,
#                            the dashboard code and the data) and start again
#   ./lab-init.sh --info     print the addresses and the password again,
#                            without starting or changing anything
#   ./lab-init.sh --clean    stop everything and remove .env, the password and
#                            the certificate, ready for saving as a template.
#                            The data volumes are kept, so the template ships with
#                            the synthetic data loaded and the pipeline run.
#
# It does four things.
#
#   1. Works out the lab address. It reads the VM's public IP from the AWS
#      instance metadata service and uses https://<a-b-c-d>.sslip.io, a name
#      that sslip.io's public DNS answers with that IP.
#   2. Gets a certificate for nginx to serve on 443, through the certbot
#      image. It makes up to three tries and stops at the first that works.
#        a. A Let's Encrypt certificate for the sslip.io name.
#        b. A Let's Encrypt certificate for the bare IP. The lab address is
#           then https://<a.b.c.d>. Let's Encrypt counts these per IP, apart
#           from the limit every sslip.io name shares.
#        c. A self-signed certificate. The lab then runs in reduced mode,
#           where browser pages stand in for the editor panes that browsers
#           block on an untrusted certificate.
#      A certificate that still fits the address is kept, and no request is
#      made. When Let's Encrypt refuses a request for being over a limit, the
#      time it gives is saved in certs/retry-after and no request goes out
#      before then. A later run puts the lab back in full mode automatically.
#   3. Creates .env with the address, the mode and a password for the editor.
#   4. Starts the workspace and nginx with docker compose.
#
# Settings come from the environment, then .env, then .env.example. The
# comments in .env.example describe every one of them and its options.
#
#   PUBLIC_IP        skips the metadata lookup, for testing off Heropa
#   LAB_HOST         skips the sslip.io name as well, for example localhost
#   LAB_CERT         letsencrypt, self-signed or none. none serves plain HTTP
#                    and is only allowed with LAB_HOST=localhost, where the
#                    browser needs no certificate to treat the page as secure.
#                    self-signed goes straight to reduced mode.
#   LAB_ACME_SERVER  the directory URL of another ACME server, for example
#                    the Let's Encrypt staging one, for testing
#   IDE_AUTH         password or none. none makes the editor ask for no
#                    password, which opens its terminal to anyone who reaches
#                    the lab address. The default is password.
#   LAB_QR           on or off. on prints a QR code for the App under the
#                    addresses, when qrencode is installed. The default is on.
#   CERTBOT_EMAIL    Let's Encrypt account address, optional
#   LAB_HTTP_PORT and LAB_HTTPS_PORT, the ports nginx publishes
#
# For a Let's Encrypt certificate the Heropa VM needs a public IP and inbound
# TCP 80 and 443 from 0.0.0.0/0. Let's Encrypt checks over port 80 from
# addresses it does not publish, so that rule cannot be narrowed.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
EXAMPLE_FILE="$SCRIPT_DIR/.env.example"
# 5.10.0 can ask for a certificate for a bare IP, which older ones cannot.
CERTBOT_IMAGE="certbot/certbot:v5.10.0"
CERT_DIR="$SCRIPT_DIR/certs"
# Kept apart from CERT_DIR so --clean leaves the Let's Encrypt account and
# certificate alone. Let's Encrypt issues the same name only five times a
# week, so a test cycle of clean and init must not ask for a new one each time.
LE_DIR="$SCRIPT_DIR/letsencrypt"

info()  { printf '\033[0;32m[INFO]\033[0m  %s\n' "$*"; }
warn()  { printf '\033[1;33m[WARN]\033[0m  %s\n' "$*" >&2; }
error() { printf '\033[0;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

compose() { docker compose --project-directory "$SCRIPT_DIR" "$@"; }

# --- arguments --------------------------------------------------------------

RESET=0
CLEAN=0
INFO=0
for arg in "$@"; do
    case "$arg" in
        --reset) RESET=1 ;;
        --clean) CLEAN=1 ;;
        --info)  INFO=1 ;;
        *)       error "Unknown option $arg. Use --reset, --clean, --info or nothing." ;;
    esac
done

# --- .env helpers -----------------------------------------------------------

# Prints the value of KEY in .env, or in the file given as the second
# argument, without surrounding quotes.
env_get() {
    local file="${2:-$ENV_FILE}"
    [[ -f "$file" ]] || return 0
    sed -n "s/^$1=//p" "$file" | tail -n 1 | sed -e 's/^"//' -e 's/"$//'
}

# Reads KEY from the environment, then .env, then .env.example.
setting() {
    local value="${!1:-}"
    [[ -n "$value" ]] || value="$(env_get "$1")"
    [[ -n "$value" ]] || value="$(env_get "$1" "$EXAMPLE_FILE")"
    printf '%s' "$value"
}

# Sets KEY to VALUE in .env, replacing an existing line or appending one.
env_set() {
    local tmp
    [[ "$2" != *[\"\$\`\\]* ]] || error "Refusing to write $1 with a quote, dollar, backtick or backslash in it."
    tmp="$(mktemp "${TMPDIR:-/tmp}/analytics-lab-env.XXXXXX")"
    KEY="$1" VALUE="$2" awk '
        BEGIN { key = ENVIRON["KEY"]; line = key "=\"" ENVIRON["VALUE"] "\"" }
        index($0, key "=") == 1 { if (!done) print line; done = 1; next }
        { print }
        END { if (!done) print line }
    ' "$ENV_FILE" > "$tmp"
    cat "$tmp" > "$ENV_FILE"
    rm -f "$tmp"
}

# Prints the lab's addresses and the editor password. The closing summary and
# --info both use it, so the two always agree.
# The controller has a port of its own on the same name, 8443 unless
# LAB_PIPES_PORT says otherwise.
pipes_url() {
    local port="${LAB_PIPES_PORT:-8443}" base="$LAB_URL"
    base="${base%%/}"
    sed -E "s#^(https?://[^/:]+)(:[0-9]+)?\$#\\1:$port/#" <<<"$base"
}

print_addresses() {
    local password="$IDE_PASSWORD"
    [[ "$IDE_AUTH" == none ]] && password="none needed"
    cat <<EOF
  Editor            $LAB_URL/ide/
  Editor password   $password
  Dashboard         $LAB_URL/dashboard/
  Pipelines         $(pipes_url)
  FHIR server       $LAB_URL/fhir/metadata
EOF
    [[ "$LAB_MODE" == full ]] || printf '  Pipeline log      %s/buildlog/\n' "$LAB_URL"
}

# A phone cannot reach an address on this machine, so a lab on localhost gets
# no QR codes.
#
# Prints a QR code for the Dashboard, so a learner can open it on a phone or tablet
# without typing the address. The Editor gets no code, because it needs a
# keyboard and a wide screen. Nothing is printed when LAB_QR is off, when
# qrencode is missing or when the output is not a terminal, because the code
# is drawn with block characters that only a terminal shows.
qr_reachable() {
    [[ "$LAB_URL" != *://localhost* && "$LAB_URL" != *://127.0.0.1* ]]
}

print_qr_code() {
    [[ "${LAB_QR:-on}" == on && -t 1 ]] || return 0
    qr_reachable || return 0
    command -v qrencode >/dev/null 2>&1 || return 0
    local code=() line
    mapfile -t code < <(qrencode -t ANSIUTF8 -m 2 "$LAB_URL/dashboard/" 2>/dev/null)
    (( ${#code[@]} )) || return 0
    echo
    echo "  Scan the QR code to open the dashboard on your phone"
    for line in "${code[@]}"; do
        printf '  %s\n' "$line"
    done
}

# Draws the QR code the start page shows for the App. An old picture is
# removed first, so the page never shows a code for an address the lab has
# left. Without qrencode there is no picture and the page leaves the code out.
write_app_qr() {
    local dir="$SCRIPT_DIR/nginx/html/qr"
    mkdir -p "$dir"
    rm -f "$dir/app.svg"
    qr_reachable || return 0
    command -v qrencode >/dev/null 2>&1 || return 0
    qrencode -t SVG -m 2 -o "$dir/app.svg" "$LAB_URL/dashboard/" 2>/dev/null \
        || rm -f "$dir/app.svg"
}

# --- --info -------------------------------------------------------------------

# Reads the addresses and the password back from .env. It asks for no
# certificate and leaves the containers alone, so it answers at once. It does
# not read the public IP again, so after the IP changes it still shows the old
# address. A full run of ./lab-init.sh is what moves the lab to a new one.
if (( INFO )); then
    [[ -f "$ENV_FILE" ]] || error "There is no .env yet, so the lab has not been set up. Run ./lab-init.sh first."
    LAB_URL="$(env_get LAB_URL)"
    LAB_MODE="$(env_get LAB_MODE)"
    IDE_PASSWORD="$(env_get IDE_PASSWORD)"
    IDE_AUTH="$(env_get IDE_AUTH)"
    LAB_QR="$(setting LAB_QR)"
    [[ -n "$LAB_URL" ]] || error ".env has no lab address yet. Run ./lab-init.sh first."

    echo
    echo "------------------------------------------------------------------------"
    echo "Open these in the browser on your own computer."
    echo
    print_addresses
    print_qr_code
    if [[ "$LAB_MODE" != full ]]; then
        echo
        echo "The lab is in REDUCED MODE. Run ./lab-init.sh to try for a trusted"
        echo "certificate again."
    fi
    echo
    echo "The tabs stopped loading? Run ./lab-init.sh to check the address and"
    echo "start anything that stopped."
    echo "------------------------------------------------------------------------"

    running=""
    if docker info >/dev/null 2>&1; then
        running="$(compose ps --services --status running 2>/dev/null || true)"
        grep -qx nginx <<<"$running" && grep -qx workspace <<<"$running" \
            || warn "The lab is not fully running. Run ./lab-init.sh to start it."
    fi
    exit 0
fi

# --- 1. preflight -----------------------------------------------------------

command -v docker  >/dev/null 2>&1 || error "docker is not installed. Run provision-heropa.sh first."
command -v curl    >/dev/null 2>&1 || error "curl is not installed."
command -v openssl >/dev/null 2>&1 || error "openssl is not installed. Run sudo apt-get install -y openssl"
docker info >/dev/null 2>&1 \
    || error "Cannot talk to Docker. Log out and back in, or run newgrp docker, then retry."

if (( CLEAN )); then
    info "Stopping the lab. The data, the pipeline results and the learner volume are kept."
    # compose needs these two to read the file at all. Their values do not
    # matter for a shutdown.
    IDE_PASSWORD=x LAB_URL=x compose down --remove-orphans
    rm -rf "$ENV_FILE" "$CERT_DIR"
    info "Removed .env and the certificate. The images and $LE_DIR are kept."
    exit 0
fi

if [[ ! -f "$ENV_FILE" ]]; then
    info "No .env found, so creating it from .env.example"
    cp "$EXAMPLE_FILE" "$ENV_FILE"
    chmod 600 "$ENV_FILE"
fi

# --- 2. lab address ---------------------------------------------------------

# IMDSv2 first, which needs a session token, then IMDSv1 for older instances.
lookup_public_ip() {
    local base="http://169.254.169.254/latest" token
    token="$(curl -fsS -m 3 -X PUT "$base/api/token" \
        -H 'X-aws-ec2-metadata-token-ttl-seconds: 60' 2>/dev/null || true)"
    if [[ -n "$token" ]]; then
        curl -fsS -m 3 -H "X-aws-ec2-metadata-token: $token" \
            "$base/meta-data/public-ipv4" 2>/dev/null && return 0
    fi
    curl -fsS -m 3 "$base/meta-data/public-ipv4" 2>/dev/null
}

# NAME_HOST is the name the lab asks a certificate for first. PUBLIC_IP stays
# empty when LAB_HOST is given, and then no certificate for a bare IP is tried.
NAME_HOST="$(setting LAB_HOST)"
if [[ -z "$NAME_HOST" ]]; then
    PUBLIC_IP="$(setting PUBLIC_IP)"
    PUBLIC_IP="${PUBLIC_IP:-$(lookup_public_ip || true)}"
    [[ "$PUBLIC_IP" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] \
        || error "Could not read a public IPv4 address. Check that the VM has a public IP in Heropa, or set PUBLIC_IP."
    info "Public IP is $PUBLIC_IP"
    NAME_HOST="${PUBLIC_IP//./-}.sslip.io"
else
    PUBLIC_IP=""
fi

HTTP_PORT="$(setting LAB_HTTP_PORT)";   HTTP_PORT="${HTTP_PORT:-80}"
HTTPS_PORT="$(setting LAB_HTTPS_PORT)"; HTTPS_PORT="${HTTPS_PORT:-443}"
LAB_CERT="$(setting LAB_CERT)"
LAB_CERT="${LAB_CERT:-letsencrypt}"
[[ "$LAB_CERT" == letsencrypt || "$LAB_CERT" == self-signed || "$LAB_CERT" == none ]] \
    || error "LAB_CERT must be letsencrypt, self-signed or none, not $LAB_CERT"
IDE_AUTH="$(setting IDE_AUTH)"
IDE_AUTH="${IDE_AUTH:-password}"
[[ "$IDE_AUTH" == password || "$IDE_AUTH" == none ]] \
    || error "IDE_AUTH must be password or none, not $IDE_AUTH"
LAB_QR="$(setting LAB_QR)"
LAB_QR="${LAB_QR:-on}"
[[ "$LAB_QR" == on || "$LAB_QR" == off ]] \
    || error "LAB_QR must be on or off, not $LAB_QR"
CERTBOT_EMAIL="$(setting CERTBOT_EMAIL)"
ACME_SERVER="$(setting LAB_ACME_SERVER)"

if [[ "$LAB_CERT" == none ]]; then
    # The editor's web views need a secure page. Without a certificate only
    # localhost counts as one.
    [[ "$NAME_HOST" == localhost || "$NAME_HOST" == 127.0.0.1 ]] \
        || error "LAB_CERT=none only works with LAB_HOST=localhost."
fi

# --- 3. certificate ---------------------------------------------------------

mkdir -p "$CERT_DIR"

# A certificate this close to its end is replaced. The ones for a bare IP last
# six days, so the margin has to be short.
MIN_DAYS_LEFT=2

# True when lab.crt is for HOST, which may be a name or an IP, and has the
# margin above left.
cert_fits() {
    local host="$1" check=-checkhost
    [[ -s "$CERT_DIR/lab.crt" && -s "$CERT_DIR/lab.key" ]] || return 1
    [[ "$host" =~ ^[0-9.]+$ ]] && check=-checkip
    openssl x509 -in "$CERT_DIR/lab.crt" -noout "$check" "$host" 2>/dev/null | grep -q 'does match' \
        && openssl x509 -in "$CERT_DIR/lab.crt" -noout -checkend $(( MIN_DAYS_LEFT * 86400 )) >/dev/null 2>&1
}

# True when lab.crt signed itself, which is how a fallback or test certificate
# is told apart from a Let's Encrypt one.
cert_self_signed() {
    [[ "$(openssl x509 -in "$CERT_DIR/lab.crt" -noout -subject 2>/dev/null | sed 's/^subject=//')" \
        == "$(openssl x509 -in "$CERT_DIR/lab.crt" -noout -issuer 2>/dev/null | sed 's/^issuer=//')" ]]
}

make_self_signed() {
    local san="DNS:$NAME_HOST"
    [[ -n "$PUBLIC_IP" ]] && san="$san,IP:$PUBLIC_IP"
    rm -f "$CERT_DIR/lab.crt" "$CERT_DIR/lab.key"
    openssl req -x509 -newkey rsa:2048 -nodes -days 825 \
        -subj "/CN=$NAME_HOST" -addext "subjectAltName=$san" \
        -keyout "$CERT_DIR/lab.key" -out "$CERT_DIR/lab.crt" 2>/dev/null
    chmod 644 "$CERT_DIR/lab.key"   # read by nginx inside its container
}

# Let's Encrypt says when to come back after it refuses a request for being
# over a limit. That time is kept here per name or IP, and no request for it
# goes out before then. Delete the file to ask again at once.
RETRY_FILE="$CERT_DIR/retry-after"

# Prints the saved time for IDENT as seconds since 1970, or nothing.
retry_time() {
    [[ -f "$RETRY_FILE" ]] || return 0
    awk -v id="$1" '$1 == id { t = $2 } END { if (t != "") print t }' "$RETRY_FILE"
}

retry_save() {
    local tmp
    tmp="$(mktemp "${TMPDIR:-/tmp}/analytics-lab-retry.XXXXXX")"
    [[ -f "$RETRY_FILE" ]] && awk -v id="$1" '$1 != id' "$RETRY_FILE" > "$tmp"
    printf '%s %s\n' "$1" "$2" >> "$tmp"
    cat "$tmp" > "$RETRY_FILE"
    rm -f "$tmp"
}

# Reads certbot's output in FILE. When it holds a refusal for being over a
# limit, prints the time to come back as seconds since 1970. An hour from now
# is used when the refusal names no time.
rate_limit_until() {
    local file="$1" stamp until
    grep -qiE 'rateLimited|too many (certificates|new orders|failed authorizations|registrations)' "$file" || return 0
    stamp="$(grep -oiE 'retry after [0-9]{4}-[0-9]{2}-[0-9]{2}[ T][0-9]{2}:[0-9]{2}:[0-9]{2}' "$file" | head -n 1 | sed -E 's/^retry after //I; s/T/ /' || true)"
    until=""
    [[ -n "$stamp" ]] && until="$(date -u -d "$stamp UTC" +%s 2>/dev/null || true)"
    [[ -n "$until" ]] || until=$(( $(date +%s) + 3600 ))
    printf '%s' "$until"
}

show_time() { date -d "@$1" '+%H:%M on %d %b' 2>/dev/null || printf 'later'; }

NGINX_STOPPED=0
CERT_PROBLEM=""      # why the last request failed, in words for the learner
CERT_RETRY_AT=""     # the earliest saved time to ask again, when there is one

# Asks Let's Encrypt for a certificate and installs it as lab.crt and lab.key.
# KIND is name or ip, and IDENT is the name or the IP. Returns 1 on any
# failure, after setting CERT_PROBLEM, and never stops the script.
request_cert() {
    local kind="$1" ident="$2" cert_name log until now
    local -a args
    now="$(date +%s)"

    until="$(retry_time "$ident")"
    if [[ -n "$until" ]] && (( until > now )); then
        info "Not asking for a certificate for $ident before $(show_time "$until"), the time Let's Encrypt gave"
        CERT_PROBLEM="Let's Encrypt is over its limit for this address"
        [[ -z "$CERT_RETRY_AT" ]] || (( until < CERT_RETRY_AT )) && CERT_RETRY_AT="$until"
        return 1
    fi

    info "Requesting a Let's Encrypt certificate for $ident"
    args=(certonly --standalone --non-interactive --agree-tos --keep-until-expiring)
    if [[ -n "$CERTBOT_EMAIL" ]]; then
        args+=(--email "$CERTBOT_EMAIL")
    else
        args+=(--register-unsafely-without-email)
    fi
    [[ -n "$ACME_SERVER" ]] && args+=(--server "$ACME_SERVER")
    if [[ "$kind" == ip ]]; then
        # Let's Encrypt gives a certificate for an IP only on its short profile.
        cert_name="ip-${ident//./-}"
        args+=(--cert-name "$cert_name" --ip-address "$ident" --required-profile shortlived)
    else
        cert_name="$ident"
        args+=(--cert-name "$cert_name" -d "$ident")
    fi

    # certbot answers the check on port 80 itself, so nginx gives the port up
    # for the minute this takes. Section 4 starts it again.
    if (( ! NGINX_STOPPED )); then
        docker stop an-nginx >/dev/null 2>&1 || true
        NGINX_STOPPED=1
    fi
    mkdir -p "$LE_DIR"
    log="$CERT_DIR/certbot-$kind.log"
    if ! docker run --rm -p "$HTTP_PORT:80" -v "$LE_DIR:/etc/letsencrypt" "$CERTBOT_IMAGE" \
            "${args[@]}" > "$log" 2>&1; then
        until="$(rate_limit_until "$log")"
        if [[ -n "$until" ]]; then
            retry_save "$ident" "$until"
            [[ -z "$CERT_RETRY_AT" ]] || (( until < CERT_RETRY_AT )) && CERT_RETRY_AT="$until"
            CERT_PROBLEM="Let's Encrypt is over its limit for this address"
            warn "Let's Encrypt refused $ident for being over a limit. It can be asked again after $(show_time "$until")."
        elif grep -qiE 'requests\.exceptions|Max retries exceeded|Name or service not known' "$log"; then
            CERT_PROBLEM="this VM could not reach Let's Encrypt"
            warn "This VM could not reach Let's Encrypt to ask for $ident. Check its outbound internet access."
        elif grep -qiE 'Timeout during connect|likely firewall|Fetching http' "$log"; then
            CERT_PROBLEM="Let's Encrypt could not reach this VM on port 80"
            warn "Let's Encrypt could not reach $ident on port 80. Check that the Heropa network rules allow inbound TCP 80 from 0.0.0.0/0."
        else
            CERT_PROBLEM="the request to Let's Encrypt failed"
            warn "The certificate request for $ident failed. The details are in $log"
        fi
        return 1
    fi

    # certbot writes as root and keeps symlinks under live/. Copy plain files
    # that nginx can read and this user can replace later.
    if ! docker run --rm -v "$LE_DIR:/etc/letsencrypt" -v "$CERT_DIR:/out" \
            --entrypoint sh "$CERTBOT_IMAGE" -c '
                cp -L "/etc/letsencrypt/live/$1/fullchain.pem" /out/lab.crt &&
                cp -L "/etc/letsencrypt/live/$1/privkey.pem" /out/lab.key &&
                chown "$2" /out/lab.crt /out/lab.key &&
                chmod 644 /out/lab.crt /out/lab.key' sh "$cert_name" "$(id -u):$(id -g)" >> "$log" 2>&1; then
        CERT_PROBLEM="the new certificate could not be copied into place"
        warn "Could not copy the certificate out of $LE_DIR. The details are in $log"
        return 1
    fi
    CERT_PROBLEM=""
}

# The lab runs in one of two modes. In full mode the browser trusts the
# certificate and every pane of the editor works. In reduced mode the
# certificate is self-signed, which browsers refuse for the editor's web
# views, so the guide, build log and output panes are replaced by browser
# pages.
LAB_MODE="full"
LAB_HOST="$NAME_HOST"

case "$LAB_CERT" in
    none)
        ;;
    self-signed)
        LAB_MODE="reduced"
        CERT_PROBLEM="LAB_CERT is set to self-signed"
        if ! cert_fits "$NAME_HOST" || ! cert_self_signed; then
            info "Making a self-signed certificate for $NAME_HOST"
            make_self_signed
        fi
        ;;
    letsencrypt)
        # Three tries, in this order. The name first, then the bare IP, which
        # Let's Encrypt counts against a limit of its own, then a self-signed
        # certificate so the lab still starts.
        if cert_fits "$NAME_HOST" && ! cert_self_signed; then
            info "The Let's Encrypt certificate for $NAME_HOST is already in place"
        elif [[ -n "$PUBLIC_IP" ]] && cert_fits "$PUBLIC_IP" && ! cert_self_signed; then
            info "The Let's Encrypt certificate for $PUBLIC_IP is already in place"
            LAB_HOST="$PUBLIC_IP"
        elif request_cert name "$NAME_HOST"; then
            info "Got a certificate for $NAME_HOST"
        elif [[ -n "$PUBLIC_IP" ]] && request_cert ip "$PUBLIC_IP"; then
            info "Got a certificate for $PUBLIC_IP, so the lab uses the IP as its address"
            LAB_HOST="$PUBLIC_IP"
        else
            LAB_MODE="reduced"
            if ! cert_fits "$NAME_HOST" || ! cert_self_signed; then
                make_self_signed
            fi
            warn "No trusted certificate, so the lab starts in reduced mode with a self-signed one."
        fi
        ;;
esac

if [[ "$LAB_CERT" == none ]]; then
    LAB_URL="http://$LAB_HOST"
    [[ "$HTTP_PORT" == 80 ]] || LAB_URL="$LAB_URL:$HTTP_PORT"
    LAB_PORT="$HTTP_PORT"
    NGINX_CONF="lab-http"
    info "The lab will answer at $LAB_URL over plain HTTP, for a local test"
else
    LAB_URL="https://$LAB_HOST"
    [[ "$HTTPS_PORT" == 443 ]] || LAB_URL="$LAB_URL:$HTTPS_PORT"
    LAB_PORT="$HTTPS_PORT"
    NGINX_CONF="lab-https"
    info "The lab will answer at $LAB_URL in $LAB_MODE mode"
fi

# --- 4. .env ----------------------------------------------------------------

# The password is a code of four digits, which is easy to read off the
# terminal and type. It is made once and kept, so a second run prints the same
# one. It never starts with 0, so nothing on the way reads it as a number and
# drops the zero. Four digits are enough here because the editor allows only
# a few wrong tries an hour and a lab lasts a few hours.
IDE_PASSWORD="$(env_get IDE_PASSWORD)"
if [[ -z "$IDE_PASSWORD" ]]; then
    IDE_PASSWORD="$(( 1000 + $(od -An -N4 -tu4 /dev/urandom | tr -d ' ') % 9000 ))"
    info "Created a password for the editor"
fi

# What the last run left, kept to tell the learner what changed.
PREV_URL="$(env_get LAB_URL)"
PREV_MODE="$(env_get LAB_MODE)"

env_set LAB_URL        "$LAB_URL"
env_set LAB_PIPES_URL  "$(pipes_url)"
env_set LAB_MODE       "$LAB_MODE"
env_set IDE_PASSWORD   "$IDE_PASSWORD"
env_set IDE_AUTH       "$IDE_AUTH"
env_set LAB_CERT       "$LAB_CERT"
env_set LAB_NGINX_CONF "$NGINX_CONF"
env_set LAB_HTTP_PORT  "$HTTP_PORT"
env_set LAB_HTTPS_PORT "$HTTPS_PORT"

write_app_qr

# --- 5. start ---------------------------------------------------------------

if (( RESET )); then
    warn "Throwing away the learner's changes and starting again"
    compose down --volumes --remove-orphans
fi

docker image inspect analytics-codelab-workspace:local >/dev/null 2>&1 \
    || warn "The workspace image is not built yet. Building it now takes several minutes."

info "Starting the lab"
compose up -d --remove-orphans
# nginx reads the certificate and LAB_URL only when it starts.
compose restart nginx >/dev/null

# The check goes to nginx on this VM, with the lab name pinned to loopback, so
# it works whether or not the VM can reach its own public address. The
# certificate is not checked here, since reduced mode has an untrusted one.
info "Waiting for the editor to answer"
ready=0
for _ in $(seq 1 60); do
    if curl -fks -m 5 -o /dev/null --connect-to "$LAB_HOST:$LAB_PORT:127.0.0.1:$LAB_PORT" "$LAB_URL/ide/healthz"; then
        ready=1
        break
    fi
    sleep 2
done
(( ready )) || warn "The editor did not answer yet. Check with docker compose logs workspace"

# --- 6. what to tell the learner --------------------------------------------

# The closing message is what a learner acts on, above all after a restart of
# the VM. It gives the addresses, says what changed since the last run and
# what to do about it.

if [[ "$LAB_MODE" == full ]]; then
    headline="The lab is ready. Open these in the browser on your own computer."
else
    headline="The lab is ready, in REDUCED MODE. Your code, the build and the app all work."
fi

# With IDE_AUTH=none the editor asks for nothing, and print_addresses says so
# in place of the password.
if [[ "$IDE_AUTH" == none ]]; then
    open_editor="Open the Editor address. It asks for no password."
    password_note="Not asked for on this lab."
else
    open_editor="Open the Editor address and enter the password."
    password_note="The same as before."
fi

cat <<EOF

------------------------------------------------------------------------
$headline

EOF
print_addresses
print_qr_code

if [[ -z "$PREV_URL" ]]; then
    cat <<EOF

First steps
  1. $open_editor
  2. Click Open dashboard at the very bottom of the Editor. The dashboard
     opens in a second tab. The Pipelines address is the FHIR Data Pipes
     controller. Open it in a third tab when the manual asks you to.
EOF
else
    echo
    echo "Since the last run"
    if [[ "$PREV_URL" == "$LAB_URL" ]]; then
        cat <<EOF
  Address    The same as before. Tabs you still have open work again after
             a reload.
EOF
    else
        cat <<EOF
  Address    CHANGED. It was $PREV_URL
             Close the old Editor, Dashboard and Pipelines tabs. They no longer work. Open
             the two addresses above.
EOF
    fi
    echo "  Password   $password_note"
    if (( RESET )); then
        echo "  Your code  Replaced with the starting ViewDefinitions, dashboard and data, because of --reset."
    else
        echo "  Your code  Kept as you left it."
    fi
    if [[ "$PREV_MODE" == reduced && "$LAB_MODE" == full ]]; then
        cat <<EOF
  Mode       Back to full mode. The Guide, Build log and Output areas are in
             the Editor again.
EOF
    fi
fi

if [[ "$LAB_MODE" == full && -n "$PUBLIC_IP" && "$LAB_HOST" == "$PUBLIC_IP" ]]; then
    cat <<EOF

Note
  These addresses use the plain IP of the VM. The certificate for the usual
  name was refused, so the lab got one for the IP. They work the same way.
EOF
fi

if [[ "$LAB_MODE" == reduced ]]; then
    again="Run ./lab-init.sh again later. It asks for a trusted certificate again
  and moves the lab to full mode when it gets one."
    [[ -n "$CERT_RETRY_AT" ]] && again="Run ./lab-init.sh again after $(show_time "$CERT_RETRY_AT"). It asks for a trusted
  certificate again and moves the lab to full mode when it gets one."
    [[ "$LAB_CERT" == self-signed ]] && again="Set LAB_CERT to letsencrypt on Heropa, or to none with LAB_HOST=localhost
  for a local test."
    cat <<EOF

Why reduced mode
  The lab could not get a certificate that browsers trust, because
  $CERT_PROBLEM. It uses one it made itself.

What is different
  1. Your browser shows a warning page the first time you open the Editor.
     Click Advanced, then Proceed. You do this once.
  2. The Editor has no Guide, Build log or Output area. Use these instead.
       Guide       the course manual in Heropa
       Pipeline logthe Pipeline log address above, in its own browser tab
       Output      the strip along the bottom of the Dashboard tab
     The buttons at the bottom of the Editor open these pages for you.

To get full mode
  $again
EOF
fi

if [[ "$IDE_AUTH" == none && "$LAB_HOST" != localhost && "$LAB_HOST" != 127.0.0.1 ]]; then
    warn "IDE_AUTH is none. Anyone who reaches $LAB_URL/ide/ gets the editor and its terminal without a password. Set IDE_AUTH to password in .env and run this again unless the inbound rules let in only a network you trust."
fi

cat <<EOF

Lost these details? Run ./lab-init.sh --info to print them again.
The tabs stopped loading? Run ./lab-init.sh again. It is safe at any time.
------------------------------------------------------------------------
EOF
