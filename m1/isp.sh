#!/bin/bash

# Параметры стенда; переменные можно задать перед запуском.
ISP_HOSTNAME="${ISP_HOSTNAME:-isp}"
ISP_TIMEZONE="${ISP_TIMEZONE:-Europe/Moscow}"
ISP_WAN_IF="${ISP_WAN_IF:-ens3}"
ISP_NAT_HQ_NET="${ISP_NAT_HQ_NET:-172.16.1.0/28}"
ISP_NAT_BR_NET="${ISP_NAT_BR_NET:-172.16.2.0/28}"
RTR_USER="${RTR_USER:-net_admin}"
RTR_PASS="${RTR_PASS:-P@ssw0rd}"
HQ_RTR_NAME="${HQ_RTR_NAME:-hq-rtr}"
BR_RTR_NAME="${BR_RTR_NAME:-br-rtr}"
HQ_RTR_IP="${HQ_RTR_IP:-172.16.1.2}"
BR_RTR_IP="${BR_RTR_IP:-172.16.2.2}"
HQ_GATEWAY_IP="${HQ_GATEWAY_IP:-172.16.1.1}"
BR_GATEWAY_IP="${BR_GATEWAY_IP:-172.16.2.1}"
DOMAIN_NAME="${DOMAIN_NAME:-au-team.irpo}"
DNS_IP="${DNS_IP:-10.10.100.2}"
RTR_TIMEZONE="${RTR_TIMEZONE:-utc+3}"
RTR_DEFAULT_ROUTE="${RTR_DEFAULT_ROUTE:-0.0.0.0/0}"
TUNNEL_IF="${TUNNEL_IF:-tunnel.0}"
HQ_GRE_ADDRESS="${HQ_GRE_ADDRESS:-10.10.10.1/30}"
BR_GRE_ADDRESS="${BR_GRE_ADDRESS:-10.10.10.2/30}"
HQ_GRE_PEER_IP="${HQ_GRE_PEER_IP:-10.10.10.2}"
BR_GRE_PEER_IP="${BR_GRE_PEER_IP:-10.10.10.1}"
HQ_OSPF_ROUTER_ID="${HQ_OSPF_ROUTER_ID:-10.10.10.1}"
BR_OSPF_ROUTER_ID="${BR_OSPF_ROUTER_ID:-10.10.10.2}"
OSPF_ID="${OSPF_ID:-1}"
OSPF_AREA="${OSPF_AREA:-0}"
OSPF_KEY_ID="${OSPF_KEY_ID:-1}"
OSPF_KEY="${OSPF_KEY:-P@ssw0rd}"
HQ_OSPF_NETWORKS="${HQ_OSPF_NETWORKS:-10.10.10.0/30 10.10.100.0/27 10.10.200.0/28 10.10.30.0/29}"
BR_OSPF_NETWORKS="${BR_OSPF_NETWORKS:-10.10.10.0/30 10.20.10.0/30}"
RTR_WAN_IF="${RTR_WAN_IF:-isp}"
HQ_VLAN100_IF="${HQ_VLAN100_IF:-vl100}"
HQ_VLAN200_IF="${HQ_VLAN200_IF:-vl200}"
HQ_VLAN999_IF="${HQ_VLAN999_IF:-vl999}"
BR_FW_IF="${BR_FW_IF:-fw}"
HQ_POOL100_NAME="${HQ_POOL100_NAME:-VLAN100}"
HQ_POOL100_RANGE="${HQ_POOL100_RANGE:-10.10.100.1-10.10.100.30}"
HQ_POOL200_NAME="${HQ_POOL200_NAME:-VLAN200}"
HQ_POOL200_RANGE="${HQ_POOL200_RANGE:-10.10.200.1-10.10.200.14}"
HQ_POOL999_NAME="${HQ_POOL999_NAME:-VLAN999}"
HQ_POOL999_RANGE="${HQ_POOL999_RANGE:-10.10.30.1-10.10.30.6}"
BR_POOL10_NAME="${BR_POOL10_NAME:-VLAN10}"
BR_POOL10_RANGE="${BR_POOL10_RANGE:-10.20.20.1-10.20.20.14}"
BR_POOL20_NAME="${BR_POOL20_NAME:-VLAN20}"
BR_POOL20_RANGE="${BR_POOL20_RANGE:-10.20.30.1-10.20.30.6}"
BR_POOL_FW_NAME="${BR_POOL_FW_NAME:-RTR-FW}"
BR_POOL_FW_RANGE="${BR_POOL_FW_RANGE:-10.20.10.1-10.20.10.2}"
SSH_TIMEOUT="${SSH_TIMEOUT:-30}"
CLI_TIMEOUT="${CLI_TIMEOUT:-30}"
PING_COUNT="${PING_COUNT:-4}"
PING_TIMEOUT="${PING_TIMEOUT:-2}"
OSPF_WAIT_TIMEOUT="${OSPF_WAIT_TIMEOUT:-60}"
OSPF_POLL_INTERVAL="${OSPF_POLL_INTERVAL:-2}"
APT_ATTEMPTS="${APT_ATTEMPTS:-3}"
APT_RETRY_DELAY="${APT_RETRY_DELAY:-2}"
ALT_BRANCH="${ALT_BRANCH:-p10}"
ALT_ARCH="${ALT_ARCH:-}"
REPOSITORY_MIRROR="${REPOSITORY_MIRROR:-http://mirror.yandex.ru/altlinux}"
OS_RELEASE_FILE="${OS_RELEASE_FILE:-/etc/os-release}"
APT_SOURCES_FILE="${APT_SOURCES_FILE:-/etc/apt/sources.list}"
APT_SOURCES_DIR="${APT_SOURCES_DIR:-/etc/apt/sources.list.d}"
APT_YANDEX_FILE="${APT_YANDEX_FILE:-$APT_SOURCES_DIR/banan-m1-yandex.list}"
SYS_NETWORK_FILE="${SYS_NETWORK_FILE:-/etc/sysconfig/network}"
IPTABLES_STATE_FILE="${IPTABLES_STATE_FILE:-/etc/sysconfig/iptables}"

# Успешный вывод остаётся в памяти; при ошибке возвращается штатный вывод команды.
quiet_run() {
    local output status
    if output=$("$@" 2>&1); then
        return 0
    else
        status=$?
        if [[ -n "$output" ]]; then printf '%s\n' "$output" >&2;
        else printf '%s: код завершения %s.\n' "$1" "$status" >&2; fi
        return "$status"
    fi
}

retry_quiet() {
    local attempts="$1" attempt output="" status=1
    shift
    for (( attempt=1; attempt<=attempts; attempt++ )); do
        if output=$("$@" 2>&1); then return 0; else status=$?; fi
        if (( attempt < attempts && APT_RETRY_DELAY > 0 )); then
            sleep "$APT_RETRY_DELAY" || return
        fi
    done
    if [[ -n "$output" ]]; then printf '%s\n' "$output" >&2;
    else printf '%s: код завершения %s.\n' "$1" "$status" >&2; fi
    return "$status"
}

setup_yandex_repository() {
    local os_id="" os_version="" key value arch file line active url suite branch current_branch=""
    local index candidate path search new_url new_line content changed group standard_root online_alt=0 yandex_index=-1
    local source_files=() changed_files=() changed_contents=() fields=()
    [[ -r "$OS_RELEASE_FILE" ]] || { printf 'Недоступен %s.\n' "$OS_RELEASE_FILE" >&2; return 1; }
    while IFS='=' read -r key value; do
        if [[ "$key" == ID || "$key" == VERSION_ID ]]; then
            value="${value#\"}"; value="${value%\"}"
            value="${value#\'}"; value="${value%\'}"
            if [[ "$key" == ID ]]; then os_id="$value"; else os_version="$value"; fi
        fi
    done < "$OS_RELEASE_FILE"
    case "$os_id" in
        altlinux|alt) ;;
        *) printf 'Настройка зеркала поддерживается только на ALT Linux (ID=%s).\n' "$os_id" >&2; return 1 ;;
    esac
    arch="$ALT_ARCH"
    [[ -n "$arch" ]] || arch=$(uname -m) || return
    case "$arch" in
        x86_64|i586|aarch64) ;;
        *) printf 'Архитектура %s не поддерживается этим зеркалом.\n' "$arch" >&2; return 1 ;;
    esac
    case "$ALT_BRANCH" in
        ""|p10|p11) ;;
        *) printf 'Поддерживаются только ветки p10 и p11: ALT_BRANCH=%s.\n' "$ALT_BRANCH" >&2; return 1 ;;
    esac
    [[ "${os_version%%.*}" == "${ALT_BRANCH#p}" ]] || {
        printf 'ALT VERSION_ID=%s не соответствует ветке %s; источники не изменены.\n' "$os_version" "$ALT_BRANCH" >&2; return 1
    }
    [[ ! -f "$APT_SOURCES_FILE" ]] || source_files+=("$APT_SOURCES_FILE")
    if [[ -d "$APT_SOURCES_DIR" ]]; then
        for file in "$APT_SOURCES_DIR"/*.list; do [[ ! -f "$file" ]] || source_files+=("$file"); done
    fi
    # Проверяем все источники до создания копий и первой записи.
    for file in "${source_files[@]}"; do
        [[ -r "$file" ]] || { printf 'Недоступен %s.\n' "$file" >&2; return 1; }
        content=""; changed=0
        while IFS= read -r line || [[ -n "$line" ]]; do
            new_line="$line"
            active="${line%%#*}"
            fields=()
            read -r -a fields <<< "$active"
            if [[ "${fields[0]:-}" == rpm || "${fields[0]:-}" == rpm-src ]]; then
                index=1; group=""
                if [[ "${fields[1]:-}" == \[*\] ]]; then group="${fields[1]}"; index=2; fi
                url="${fields[$index]:-}"
                suite="${fields[$((index+1))]:-}"
                standard_root=0
                if [[ "$url" =~ ^(https?|ftp|rsync)://ftp\.altlinux\.(org|ru)/(pub/distributions/)?ALTLinux(/.*)?$ ||
                      "$url" =~ ^(https?|ftp|rsync)://mirror\.yandex\.ru/altlinux(/.*)?$ ]]; then standard_root=1; fi
                case "$url" in "$REPOSITORY_MIRROR"|"$REPOSITORY_MIRROR"/*) standard_root=1 ;; esac
                if [[ "$ALT_BRANCH" == p10 && "$url" == cdrom:* ]]; then new_line="# $line"; changed=1; fi
                branch=""
                for path in "$url" "$suite"; do
                    if [[ "$path" =~ (^|/)(Sisyphus|c[0-9][^/[:space:]]*)(/|$) ]]; then
                        printf 'Неподдерживаемая ветка в %s: %s\n' "$file" "$line" >&2; return 1
                    fi
                    search="$path"
                    while [[ "$search" =~ (^|/)(p[0-9]+)/branch(/|$) ]]; do
                        candidate="${BASH_REMATCH[2]}"
                        case "$candidate" in p10|p11) ;; *) printf 'Неподдерживаемая ветка %s в %s.\n' "$candidate" "$file" >&2; return 1 ;; esac
                        if [[ -n "$branch" && "$branch" != "$candidate" ]]; then printf 'Смешанные ветки ALT в %s.\n' "$file" >&2; return 1; fi
                        branch="$candidate"
                        search="${search#*"${BASH_REMATCH[0]}"}"
                    done
                done
                if [[ -n "$branch" ]]; then
                    if [[ -n "$current_branch" && "$current_branch" != "$branch" ]]; then
                        printf 'В активных источниках смешаны ветки %s и %s.\n' "$current_branch" "$branch" >&2; return 1
                    fi
                    current_branch="$branch"
                    if [[ "$group" == "[p10]" || "$group" == "[p11]" ]]; then
                        [[ "$group" == "[$branch]" ]] || { printf 'Группа подписи %s не соответствует пути %s в %s.\n' "$group" "$branch" "$file" >&2; return 1; }
                    fi
                    if (( standard_root )); then
                        [[ "${fields[0]}" != rpm ]] || online_alt=1
                        new_url="${REPOSITORY_MIRROR%/}"
                        if [[ "$url" =~ (/p[0-9]+/branch(/.*)?)$ ]]; then new_url+="${BASH_REMATCH[1]}"; fi
                        if [[ "$url" != "$new_url" ]]; then new_line="${line/"$url"/$new_url}"; changed=1; fi
                    fi
                elif (( standard_root )); then
                    printf 'Не удалось определить ветку ALT из активного источника: %s\n' "$line" >&2; return 1
                fi
            fi
            content+="$new_line"$'\n'
        done < "$file"
        if (( changed )); then changed_files+=("$file"); changed_contents+=("$content"); fi
    done
    if [[ -z "$current_branch" ]]; then
        [[ "$ALT_BRANCH" == p10 && "${os_version%%.*}" == 10 ]] || {
            printf 'В активных RPM-источниках не найдена единственная ветка p10/branch или p11/branch.\n' >&2; return 1
        }
        current_branch=p10
    fi
    [[ -z "$ALT_BRANCH" || "$ALT_BRANCH" == "$current_branch" ]] || {
        printf 'ALT_BRANCH=%s не совпадает с текущей веткой %s; миграция запрещена.\n' "$ALT_BRANCH" "$current_branch" >&2; return 1
    }
    if (( ! online_alt )); then
        [[ "$ALT_BRANCH" == p10 ]] || { printf 'Отсутствует активный сетевой источник ALT %s.\n' "$ALT_BRANCH" >&2; return 1; }
        content=""
        for (( index=0; index<${#changed_files[@]}; index++ )); do
            if [[ "${changed_files[$index]}" == "$APT_YANDEX_FILE" ]]; then yandex_index=$index; content="${changed_contents[$index]}"; fi
        done
        if (( yandex_index < 0 )) && [[ -f "$APT_YANDEX_FILE" ]]; then
            [[ -r "$APT_YANDEX_FILE" ]] || { printf 'Недоступен %s.\n' "$APT_YANDEX_FILE" >&2; return 1; }
            content="$(cat "$APT_YANDEX_FILE")"$'\n'
        fi
        content+="rpm [p10] ${REPOSITORY_MIRROR%/} p10/branch/$arch classic"$'\n'
        content+="rpm [p10] ${REPOSITORY_MIRROR%/} p10/branch/noarch classic"$'\n'
        if (( yandex_index >= 0 )); then changed_contents[$yandex_index]="$content";
        else changed_files+=("$APT_YANDEX_FILE"); changed_contents+=("$content"); fi
    fi
    for file in "${changed_files[@]}"; do
        if [[ -f "$file" && ! -e "$file.banan-m1.bak" ]]; then quiet_run cp -p "$file" "$file.banan-m1.bak" || return; fi
    done
    if (( ! online_alt )); then quiet_run mkdir -p "${APT_YANDEX_FILE%/*}" || return; fi
    for (( index=0; index<${#changed_files[@]}; index++ )); do
        printf '%s' "${changed_contents[$index]}" > "${changed_files[$index]}" || return
    done
}

ensure_dependencies() {
    local binary package mapping found existing
    local packages=() mappings=(
        expect:expect ssh:openssh-clients ping:iputils ip:iproute2
        iptables:iptables iptables-save:iptables
        hostnamectl:systemd timedatectl:systemd systemctl:systemd
    )
    for binary in apt-get rpm; do
        command -v "$binary" >/dev/null 2>&1 || { printf 'Не найдена базовая команда %s.\n' "$binary" >&2; return 1; }
    done
    quiet_run rpm -q systemd || return
    setup_yandex_repository || return
    for mapping in "${mappings[@]}"; do
        binary="${mapping%%:*}"; package="${mapping#*:}"
        if ! command -v "$binary" >/dev/null 2>&1; then
            found=0
            for existing in "${packages[@]}"; do [[ "$existing" != "$package" ]] || found=1; done
            (( found )) || packages+=("$package")
        fi
    done
    if (( ${#packages[@]} )); then
        retry_quiet "$APT_ATTEMPTS" apt-get update || return
        retry_quiet "$APT_ATTEMPTS" apt-get install -y "${packages[@]}" || return
    fi
    for mapping in "${mappings[@]}"; do
        binary="${mapping%%:*}"
        command -v "$binary" >/dev/null 2>&1 || { printf 'После установки не найдена команда %s.\n' "$binary" >&2; return 1; }
    done
    # Подключение к работающему manager проверяем, init не меняем.
    quiet_run systemctl show --property=Version --value || return
}

check_wan_router() {
    local router_ip="$1"
    if ping -c 1 -W "$PING_TIMEOUT" "$router_ip" >/dev/null 2>&1; then return 0; fi
    ping -c "$PING_COUNT" -W "$PING_TIMEOUT" "$router_ip" || :
    return 1
}

add_nat_rule_once() {
    local src_net="$1" out_if="$2"
    if iptables -t nat -C POSTROUTING -s "$src_net" -o "$out_if" -j MASQUERADE 2>/dev/null; then
        return 0
    else
        quiet_run iptables -t nat -A POSTROUTING -s "$src_net" -o "$out_if" -j MASQUERADE || return
    fi
}

save_iptables() {
    local output status
    if output=$(iptables-save 2>&1 > "$IPTABLES_STATE_FILE"); then
        return 0
    else
        status=$?
        [[ -z "$output" ]] || printf '%s\n' "$output" >&2
        return "$status"
    fi
}

configure_router() { router_session configure "$1" "$2" ""; }
check_router() { router_session check "$1" "$2" "$3"; }

router_session() {
    local mode="$1" router_name="$2" router_ip="$3" peer_ip="${4:-}" value status
    for value in "$router_name" "$router_ip" "$peer_ip" "$DOMAIN_NAME" "$DNS_IP" "$RTR_USER" "$RTR_PASS" \
        "$TUNNEL_IF" "$OSPF_KEY" "$HQ_OSPF_NETWORKS" "$BR_OSPF_NETWORKS"; do
        if [[ "$value" == *$'\n'* || "$value" == *$'\r'* ]]; then
            printf 'Параметр CLI содержит перевод строки.\n' >&2; return 1
        fi
    done
    RTR_MODE="$mode" RTR_NAME="$router_name" RTR_IP="$router_ip" GRE_PEER_IP="$peer_ip" \
    RTR_USER="$RTR_USER" RTR_PASS="$RTR_PASS" HQ_RTR_NAME="$HQ_RTR_NAME" BR_RTR_NAME="$BR_RTR_NAME" \
    HQ_RTR_IP="$HQ_RTR_IP" BR_RTR_IP="$BR_RTR_IP" HQ_GATEWAY_IP="$HQ_GATEWAY_IP" BR_GATEWAY_IP="$BR_GATEWAY_IP" \
    DOMAIN_NAME="$DOMAIN_NAME" DNS_IP="$DNS_IP" RTR_TIMEZONE="$RTR_TIMEZONE" RTR_DEFAULT_ROUTE="$RTR_DEFAULT_ROUTE" TUNNEL_IF="$TUNNEL_IF" \
    HQ_GRE_ADDRESS="$HQ_GRE_ADDRESS" BR_GRE_ADDRESS="$BR_GRE_ADDRESS" \
    HQ_OSPF_ROUTER_ID="$HQ_OSPF_ROUTER_ID" BR_OSPF_ROUTER_ID="$BR_OSPF_ROUTER_ID" \
    OSPF_ID="$OSPF_ID" OSPF_AREA="$OSPF_AREA" OSPF_KEY_ID="$OSPF_KEY_ID" OSPF_KEY="$OSPF_KEY" \
    HQ_OSPF_NETWORKS="$HQ_OSPF_NETWORKS" BR_OSPF_NETWORKS="$BR_OSPF_NETWORKS" \
    RTR_WAN_IF="$RTR_WAN_IF" HQ_VLAN100_IF="$HQ_VLAN100_IF" HQ_VLAN200_IF="$HQ_VLAN200_IF" HQ_VLAN999_IF="$HQ_VLAN999_IF" BR_FW_IF="$BR_FW_IF" \
    HQ_POOL100_NAME="$HQ_POOL100_NAME" HQ_POOL100_RANGE="$HQ_POOL100_RANGE" HQ_POOL200_NAME="$HQ_POOL200_NAME" HQ_POOL200_RANGE="$HQ_POOL200_RANGE" \
    HQ_POOL999_NAME="$HQ_POOL999_NAME" HQ_POOL999_RANGE="$HQ_POOL999_RANGE" \
    BR_POOL10_NAME="$BR_POOL10_NAME" BR_POOL10_RANGE="$BR_POOL10_RANGE" BR_POOL20_NAME="$BR_POOL20_NAME" BR_POOL20_RANGE="$BR_POOL20_RANGE" \
    BR_POOL_FW_NAME="$BR_POOL_FW_NAME" BR_POOL_FW_RANGE="$BR_POOL_FW_RANGE" \
    SSH_TIMEOUT="$SSH_TIMEOUT" CLI_TIMEOUT="$CLI_TIMEOUT" PING_COUNT="$PING_COUNT" PING_TIMEOUT="$PING_TIMEOUT" \
    OSPF_WAIT_TIMEOUT="$OSPF_WAIT_TIMEOUT" OSPF_POLL_INTERVAL="$OSPF_POLL_INTERVAL" expect <<'EXPECT'
log_user 0
match_max 65536
set timeout $env(CLI_TIMEOUT)
set spawn_id ""
set prompt_re {(?:^|[\r\n])[A-Za-z0-9_.-]+(?:\([^\r\n]*\))?([>#])[ \t]*$}
set error_re {(?:invalid (?:input|command)|unknown command|incomplete command|ambiguous command|syntax error|permission denied|authentication failed|connection (?:refused|closed|timed out)|no route to host|could not resolve hostname|host key verification failed|error:|failed:|%[ \t]*(?:error|invalid|unknown|incomplete|ambiguous))}

proc fail {output {reason ""} {code 1}} {
    global env
    if {$output ne ""} {
        puts -nonewline stderr $output
        if {[string index $output end] ne "\n"} { puts stderr "" }
    }
    if {$reason ne ""} { puts stderr $reason
    } elseif {$output eq ""} { puts stderr "Проверка EcoRouter $env(RTR_IP) не пройдена." }
    exit $code
}

proc run_command {command {seconds ""}} {
    global prompt_re error_re spawn_id env
    if {[regexp {[\r\n]} $command]} { fail "Параметр CLI содержит перевод строки.\n" }
    set timeout $env(CLI_TIMEOUT)
    if {$seconds ne ""} { set timeout $seconds }
    send -- "$command\r"
    expect {
        -nocase -re $prompt_re { set response $expect_out(buffer) }
        timeout { fail $expect_out(buffer) "Истекло время ожидания ответа от $env(RTR_IP)." }
        eof { fail $expect_out(buffer) "Сеанс SSH с $env(RTR_IP) завершился во время выполнения команды." }
    }
    if {[regexp -nocase $error_re $response]} { fail $response }
    return $response
}

proc ping_step {pattern answer} {
    global spawn_id ping_output env
    set timeout $env(CLI_TIMEOUT)
    expect {
        -nocase -re $pattern { append ping_output $expect_out(buffer); send -- "$answer\r" }
        timeout { append ping_output $expect_out(buffer); fail $ping_output "Истекло время ожидания ответа от $env(RTR_IP)." }
        eof { append ping_output $expect_out(buffer); fail $ping_output "Сеанс SSH с $env(RTR_IP) завершился во время ping." }
    }
}

proc check_gre {} {
    global env spawn_id prompt_re error_re ping_output
    set gre_output [run_command "show interface $env(TUNNEL_IF)"]
    if {![regexp -nocase {\mup\M} $gre_output] || [regexp -nocase {\mdown\M} $gre_output] ||
        ![regexp -nocase {Tunnel[ \t]+mode[ \t]*:[ \t]*GRE\M} $gre_output]} { fail $gre_output }
    set ping_output ""
    send -- "ping\r"
    ping_step {Protocol[ \t]*\[ip\][ \t]*:[ \t]*$} ""
    ping_step {Target IP address[ \t]*:[ \t]*$} $env(GRE_PEER_IP)
    ping_step {Name of (?:the )?VRF[ \t]*:[ \t]*$} ""
    ping_step {Repeat count[ \t]*\[[0-9]+\][ \t]*:[ \t]*$} $env(PING_COUNT)
    ping_step {Datagram size[ \t]*\[[0-9]+\][ \t]*:[ \t]*$} ""
    ping_step {Timeout in seconds[ \t]*\[[0-9]+\][ \t]*:[ \t]*$} $env(PING_TIMEOUT)
    ping_step {Extended commands[ \t]*\[n\][ \t]*:[ \t]*$} "n"
    ping_step {Broadcast[ \t]*\[n\][ \t]*:[ \t]*$} "n"
    set timeout [expr {$env(PING_COUNT) * ($env(PING_TIMEOUT) + 1) + $env(CLI_TIMEOUT)}]
    expect {
        -nocase -re $prompt_re { append ping_output $expect_out(buffer) }
        timeout { append ping_output $expect_out(buffer); fail $ping_output "Истекло время ожидания ответа от $env(RTR_IP)." }
        eof { append ping_output $expect_out(buffer); fail $ping_output "Сеанс SSH с $env(RTR_IP) завершился во время ping." }
    }
    if {[regexp -nocase $error_re $ping_output] ||
        ![regexp {([0-9]+) packets transmitted,[ \t]*([0-9]+) (?:packets )?received,[ \t]*([0-9]+(?:\.[0-9]+)?)% packet loss} $ping_output -> sent received loss] ||
        $sent != $env(PING_COUNT) || $received != $sent || $loss != 0} {
        fail $ping_output
    }
}

proc check_ospf {} {
    global env
    set output ""
    set deadline [expr {[clock milliseconds] + 1000 * $env(OSPF_WAIT_TIMEOUT)}]
    while {1} {
        set remaining [expr {int(ceil(($deadline - [clock milliseconds]) / 1000.0))}]
        if {$remaining <= 0} { fail $output "За $env(OSPF_WAIT_TIMEOUT) с не найден OSPF-сосед $env(GRE_PEER_IP) в Full на $env(TUNNEL_IF)." }
        set output [run_command "show ip ospf neighbor" [expr {min($remaining, $env(CLI_TIMEOUT))}]]
        foreach row [split $output "\n"] {
            set fields [regexp -all -inline {\S+} $row]
            if {[lsearch -exact $fields $env(GRE_PEER_IP)] < 0 || [lsearch -exact $fields $env(TUNNEL_IF)] < 0} { continue }
            foreach field $fields {
                if {[regexp -nocase {^Full(?:/[^ \t\r\n]+)?$} $field]} { return }
            }
        }
        set remaining_ms [expr {$deadline - [clock milliseconds]}]
        if {$remaining_ms <= 0} { fail $output "За $env(OSPF_WAIT_TIMEOUT) с не найден OSPF-сосед $env(GRE_PEER_IP) в Full на $env(TUNNEL_IF)." }
        after [expr {min($remaining_ms, int(1000 * $env(OSPF_POLL_INTERVAL)))}]
    }
}

set commands {}
if {$env(RTR_MODE) eq "configure"} {
    set hq [expr {$env(RTR_NAME) eq $env(HQ_RTR_NAME)}]
    if {!$hq && $env(RTR_NAME) ne $env(BR_RTR_NAME)} { fail "" }
    lappend commands "hostname $env(RTR_NAME)"
    if {$hq} {
        lappend commands "ip domain-name $env(DOMAIN_NAME)" "ip name-server $env(DNS_IP)"
        set gateway $env(HQ_GATEWAY_IP); set address $env(HQ_GRE_ADDRESS)
        set local_ip $env(HQ_RTR_IP); set remote_ip $env(BR_RTR_IP)
        set router_id $env(HQ_OSPF_ROUTER_ID); set networks $env(HQ_OSPF_NETWORKS)
    } else {
        lappend commands "ip name-server $env(DNS_IP)" "ip domain-name $env(DOMAIN_NAME)"
        set gateway $env(BR_GATEWAY_IP); set address $env(BR_GRE_ADDRESS)
        set local_ip $env(BR_RTR_IP); set remote_ip $env(HQ_RTR_IP)
        set router_id $env(BR_OSPF_ROUTER_ID); set networks $env(BR_OSPF_NETWORKS)
    }
    lappend commands "ntp timezone $env(RTR_TIMEZONE)" "ip route $env(RTR_DEFAULT_ROUTE) $gateway"
    lappend commands "interface $env(TUNNEL_IF)" "ip address $address" "ip tunnel $local_ip $remote_ip mode gre" "exit"
    lappend commands "router ospf $env(OSPF_ID)" "ospf router-id $router_id" "passive-interface default" "no passive-interface $env(TUNNEL_IF)"
    if {!$hq} { lappend commands "no passive-interface $env(BR_FW_IF)" }
    foreach network [regexp -all -inline {\S+} $networks] { lappend commands "network $network area $env(OSPF_AREA)" }
    lappend commands "exit" "interface $env(TUNNEL_IF)" "ip ospf authentication message-digest" "ip ospf message-digest-key $env(OSPF_KEY_ID) md5 $env(OSPF_KEY)" "exit"
    if {!$hq} {
        lappend commands "interface $env(BR_FW_IF)" "ip ospf authentication message-digest" "ip ospf message-digest-key $env(OSPF_KEY_ID) md5 $env(OSPF_KEY)" "exit"
    }
    lappend commands "interface $env(RTR_WAN_IF)" "ip nat outside" "exit"
    if {$hq} {
        foreach iface [list $env(HQ_VLAN100_IF) $env(HQ_VLAN200_IF) $env(HQ_VLAN999_IF)] {
            lappend commands "interface $iface" "ip nat inside" "exit"
        }
        set pools [list $env(HQ_POOL100_NAME) $env(HQ_POOL100_RANGE) $env(HQ_POOL200_NAME) $env(HQ_POOL200_RANGE) $env(HQ_POOL999_NAME) $env(HQ_POOL999_RANGE)]
    } else {
        lappend commands "interface $env(BR_FW_IF)" "ip nat inside" "exit"
        set pools [list $env(BR_POOL10_NAME) $env(BR_POOL10_RANGE) $env(BR_POOL20_NAME) $env(BR_POOL20_RANGE) $env(BR_POOL_FW_NAME) $env(BR_POOL_FW_RANGE)]
    }
    foreach {name range} $pools { lappend commands "ip nat pool $name $range" }
    foreach {name range} $pools { lappend commands "ip nat source dynamic inside-to-outside pool $name overload interface $env(RTR_WAN_IF)" }
} elseif {$env(RTR_MODE) ne "check"} { fail "" }

spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=$env(SSH_TIMEOUT) -o NumberOfPasswordPrompts=1 "$env(RTR_USER)@$env(RTR_IP)"
set password_sent 0
set login_output ""
set timeout $env(SSH_TIMEOUT)
expect {
    -nocase -re {yes/no} { append login_output $expect_out(buffer); send -- "yes\r"; exp_continue -continue_timer }
    -nocase -re {password:[ \t]*$} {
        append login_output $expect_out(buffer)
        if {$password_sent} { fail $login_output }
        send -- "$env(RTR_PASS)\r"
        set password_sent 1
        exp_continue -continue_timer
    }
    -nocase -re $prompt_re {
        append login_output $expect_out(buffer)
        if {[regexp -nocase $error_re $login_output]} { fail $login_output }
        set initial_mode $expect_out(1,string)
    }
    timeout { append login_output $expect_out(buffer); fail $login_output "Истекло время ожидания ответа от $env(RTR_IP)." }
    eof { append login_output $expect_out(buffer); fail $login_output "Сеанс SSH с $env(RTR_IP) завершился до получения приглашения." }
}
if {$initial_mode eq ">"} { run_command "enable" }
if {$env(RTR_MODE) eq "configure"} {
    run_command "configure"
    foreach command $commands { run_command $command }
    run_command "end"
    run_command "write memory"
} else {
    check_gre
    check_ospf
}
send -- "exit\r"
set timeout $env(CLI_TIMEOUT)
expect {
    timeout { fail $expect_out(buffer) "Истекло время ожидания завершения SSH с $env(RTR_IP)." }
    eof {
        set output $expect_out(buffer)
        set ssh_status [wait]
        if {[lindex $ssh_status 2] != 0 || [lindex $ssh_status 3] != 0 || [llength $ssh_status] > 4} {
            fail $output "SSH с $env(RTR_IP) завершился с состоянием: $ssh_status."
        }
    }
}
EXPECT
    status=$?
    return "$status"
}

main() {
    if (( EUID != 0 )); then printf 'Скрипт должен быть запущен от root.\n' >&2; return 1; fi
    ensure_dependencies || return
    check_wan_router "$HQ_RTR_IP" || return
    check_wan_router "$BR_RTR_IP" || return
    quiet_run hostnamectl set-hostname "$ISP_HOSTNAME" || return
    quiet_run timedatectl set-timezone "$ISP_TIMEZONE" || return
    if grep -q '^HOSTNAME=' "$SYS_NETWORK_FILE" 2>/dev/null; then
        quiet_run sed -i "s/^HOSTNAME=.*/HOSTNAME=$ISP_HOSTNAME/" "$SYS_NETWORK_FILE" || return
    else
        printf 'HOSTNAME=%s\n' "$ISP_HOSTNAME" >> "$SYS_NETWORK_FILE" || return
    fi
    add_nat_rule_once "$ISP_NAT_HQ_NET" "$ISP_WAN_IF" || return
    add_nat_rule_once "$ISP_NAT_BR_NET" "$ISP_WAN_IF" || return
    save_iptables || return
    quiet_run systemctl enable --now iptables.service || return
    quiet_run hostname || return
    quiet_run timedatectl || return
    quiet_run ip -br a || return
    quiet_run iptables -t nat -L POSTROUTING -n -v || return
    configure_router "$HQ_RTR_NAME" "$HQ_RTR_IP" || return
    configure_router "$BR_RTR_NAME" "$BR_RTR_IP" || return
    check_router "$HQ_RTR_NAME" "$HQ_RTR_IP" "$HQ_GRE_PEER_IP" || return
    check_router "$BR_RTR_NAME" "$BR_RTR_IP" "$BR_GRE_PEER_IP" || return
}

if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    set -Eeuo pipefail
    main "$@"
fi

