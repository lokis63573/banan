#!/bin/bash
set -Eeuo pipefail

trap 'printf "[ERROR] Ошибка в строке %s, код %s. Выполнение остановлено.\n" "$LINENO" "$?" >&2' ERR

RTR_USER="net_admin"
RTR_PASS="P@ssw0rd"

add_nat_rule_once() {
    local src_net="$1"
    local out_if="$2"

    if iptables -t nat -C POSTROUTING -s "$src_net" -o "$out_if" -j MASQUERADE 2>/dev/null; then
        echo "[OK] NAT уже настроен для $src_net через $out_if"
    else
        echo "[+] Добавляю NAT для $src_net через $out_if"
        iptables -t nat -A POSTROUTING -s "$src_net" -o "$out_if" -j MASQUERADE
    fi
}

ensure_expect() {
    if ! command -v expect >/dev/null 2>&1; then
        echo "[+] expect не найден, устанавливаю..."
        apt-get update
        apt-get install -y expect
    fi

    if ! command -v expect >/dev/null 2>&1; then
        echo "[-] expect не установился" >&2
        return 1
    fi
}

configure_router() {
    local router_name="$1"
    local router_ip="$2"

    echo "===== CONFIG $router_name ($router_ip) ====="

    RTR_NAME="$router_name" RTR_IP="$router_ip" \
    RTR_USER="$RTR_USER" RTR_PASS="$RTR_PASS" expect <<'EXPECT'
set timeout 30
set router_name $env(RTR_NAME)
set router_ip $env(RTR_IP)
set router_user $env(RTR_USER)
set router_pass $env(RTR_PASS)

# Принимаем исходное имя и имена после предыдущего запуска, включая config-режимы.
set prompt_re {(?:^|[\r\n])(?:ecorouter|hq-rtr|br-rtr)(?:\([^\r\n]*\))?([>#])[ \t]*$}
set error_re {(?:invalid (?:input|command)|unknown command|incomplete command|ambiguous command|syntax error|permission denied|authentication failed|connection (?:refused|closed|timed out)|no route to host|could not resolve hostname|host key verification failed|error:|failed:|%[ \t]*(?:error|invalid|unknown|incomplete|ambiguous))}

proc fail {message} {
    global router_name
    puts stderr "\n\[ERROR\] $router_name: $message"
    exit 1
}

proc run_command {command} {
    global prompt_re error_re spawn_id
    send -- "$command\r"
    expect {
        -nocase -re $error_re { fail "ошибка CLI при выполнении '$command': $expect_out(0,string)" }
        -nocase -re $prompt_re { return }
        timeout { fail "нет приглашения после команды '$command'" }
        eof { fail "SSH завершился во время команды '$command'" }
    }
}

switch -- $router_name {
    hq-rtr {
        set commands {
            {hostname hq-rtr}
            {ip domain-name au-team.irpo}
            {ip name-server 10.10.100.2}
            {ntp timezone utc+3}
            {ip route 0.0.0.0/0 172.16.1.1}
            {interface tunnel.0}
            {ip address 10.10.10.1/30}
            {ip tunnel 172.16.1.2 172.16.2.2 mode gre}
            {exit}
            {router ospf 1}
            {ospf router-id 10.10.10.1}
            {passive-interface default}
            {no passive-interface tunnel.0}
            {network 10.10.10.0/30 area 0}
            {network 10.10.100.0/27 area 0}
            {network 10.10.200.0/28 area 0}
            {network 10.10.30.0/29 area 0}
            {exit}
            {interface tunnel.0}
            {ip ospf authentication message-digest}
            {ip ospf message-digest-key 1 md5 P@ssw0rd}
            {exit}
            {interface isp}
            {ip nat outside}
            {exit}
            {interface vl100}
            {ip nat inside}
            {exit}
            {interface vl200}
            {ip nat inside}
            {exit}
            {interface vl999}
            {ip nat inside}
            {exit}
            {ip nat pool VLAN100 10.10.100.1-10.10.100.30}
            {ip nat pool VLAN200 10.10.200.1-10.10.200.14}
            {ip nat pool VLAN999 10.10.30.1-10.10.30.6}
            {ip nat source dynamic inside-to-outside pool VLAN100 overload interface isp}
            {ip nat source dynamic inside-to-outside pool VLAN200 overload interface isp}
            {ip nat source dynamic inside-to-outside pool VLAN999 overload interface isp}
        }
    }
    br-rtr {
        set commands {
            {hostname br-rtr}
            {ip name-server 10.10.100.2}
            {ip domain-name au-team.irpo}
            {ntp timezone utc+3}
            {ip route 0.0.0.0/0 172.16.2.1}
            {interface tunnel.0}
            {ip address 10.10.10.2/30}
            {ip tunnel 172.16.2.2 172.16.1.2 mode gre}
            {exit}
            {router ospf 1}
            {ospf router-id 10.10.10.2}
            {passive-interface default}
            {no passive-interface tunnel.0}
            {no passive-interface fw}
            {network 10.10.10.0/30 area 0}
            {network 10.20.10.0/30 area 0}
            {exit}
            {interface tunnel.0}
            {ip ospf authentication message-digest}
            {ip ospf message-digest-key 1 md5 P@ssw0rd}
            {exit}
            {interface fw}
            {ip ospf authentication message-digest}
            {ip ospf message-digest-key 1 md5 P@ssw0rd}
            {exit}
            {interface isp}
            {ip nat outside}
            {exit}
            {interface fw}
            {ip nat inside}
            {exit}
            {ip nat pool VLAN10 10.20.20.1-10.20.20.14}
            {ip nat pool VLAN20 10.20.30.1-10.20.30.6}
            {ip nat pool RTR-FW 10.20.10.1-10.20.10.2}
            {ip nat source dynamic inside-to-outside pool VLAN10 overload interface isp}
            {ip nat source dynamic inside-to-outside pool VLAN20 overload interface isp}
            {ip nat source dynamic inside-to-outside pool RTR-FW overload interface isp}
        }
    }
    default { fail "неизвестный маршрутизатор '$router_name'" }
}

spawn ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ConnectTimeout=30 -o NumberOfPasswordPrompts=1 "$router_user@$router_ip"
set password_sent 0
expect {
    -nocase -re $error_re { fail "ошибка подключения: $expect_out(0,string)" }
    -nocase -re {yes/no} { send -- "yes\r"; exp_continue }
    -nocase -re {password:[ \t]*$} {
        if {$password_sent} { fail "SSH повторно запросил пароль" }
        send -- "$router_pass\r"
        set password_sent 1
        exp_continue
    }
    -nocase -re $prompt_re { set initial_mode $expect_out(1,string) }
    timeout { fail "таймаут подключения к $router_ip" }
    eof { fail "SSH завершился до получения приглашения" }
}

if {$initial_mode eq ">"} { run_command "enable" }
run_command "configure"
foreach command $commands { run_command $command }
run_command "end"
run_command "write memory"
send -- "exit\r"
expect {
    -nocase -re $error_re { fail "ошибка завершения SSH: $expect_out(0,string)" }
    timeout { fail "SSH не завершился после exit" }
    eof {
        set ssh_status [wait]
        if {[lindex $ssh_status 2] != 0 || [lindex $ssh_status 3] != 0 || [llength $ssh_status] > 4} {
            fail "SSH завершился с ошибкой: $ssh_status"
        }
    }
}
EXPECT

    echo "===== $router_name DONE ====="
}

main() {
    if (( EUID != 0 )); then
        echo "[ERROR] Скрипт должен быть запущен от root." >&2
        return 1
    fi

    echo "===== MODULE 1: ISP CONFIG ====="
    hostnamectl set-hostname isp
    timedatectl set-timezone Europe/Moscow

    if grep -q '^HOSTNAME=' /etc/sysconfig/network; then
        sed -i 's/^HOSTNAME=.*/HOSTNAME=isp/' /etc/sysconfig/network
    else
        echo 'HOSTNAME=isp' >> /etc/sysconfig/network
    fi

    add_nat_rule_once 172.16.1.0/28 ens3
    add_nat_rule_once 172.16.2.0/28 ens3
    iptables-save > /etc/sysconfig/iptables
    systemctl enable --now iptables.service

    echo
    echo "===== ISP CHECK ====="
    hostname
    timedatectl | grep "Time zone"
    ip -br a
    iptables -t nat -L POSTROUTING -n -v

    echo
    echo "===== CHECK ROUTERS ====="
    if ! ping -c 2 172.16.1.2; then
        echo "[-] HQ-RTR 172.16.1.2 недоступен" >&2
        return 1
    fi
    if ! ping -c 2 172.16.2.2; then
        echo "[-] BR-RTR 172.16.2.2 недоступен" >&2
        return 1
    fi
    echo "[+] Роутеры доступны"

    ensure_expect
    configure_router hq-rtr 172.16.1.2
    configure_router br-rtr 172.16.2.2

    echo
    echo "===== MODULE 1 ISP + RTR DONE ====="
    echo "=== 1/2 модуля выполнено ==="
}

if [[ $BASH_SOURCE == "$0" ]]; then
    main "$@"
fi

