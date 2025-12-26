#!/bin/sh
# ================================================================
# 作者：llodys
# 仓库：https://github.com/llodys/snell
# 描述: 此脚本用于在 Alpine Linux 系统上安装和管理 Snell 代理服务。
# ================================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BLUE='\033[0;34m'
WHITE='\033[0;37m'
RESET='\033[0m'

current_version="2.7"

SNELL_VERSION=""
SNELL_COMMAND=""
PSK=""

INSTALL_DIR="/usr/local/bin"
SNELL_CONF_DIR="/etc/snell"
SNELL_CONF_FILE="${SNELL_CONF_DIR}/users/snell-main.conf"
OPENRC_SERVICE_FILE="/etc/init.d/snell"

check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 请以 root 权限运行此脚本。${RESET}"
        exit 1
    fi
}

check_system() {
    if [ ! -f /etc/alpine-release ]; then
        echo -e "${RED}错误: 此脚本仅适用于 Alpine Linux 系统${RESET}"
        exit 1
    fi
}

install_dependencies() {
    echo -e "${CYAN}正在更新软件源并安装基础依赖...${RESET}"
    apk update
    apk add curl wget unzip openssl iptables openrc net-tools file
    
    echo -e "${CYAN}正在为 Alpine 安装 glibc 兼容环境...${RESET}"
    
    apk add gcompat
    apk del glibc glibc-bin glibc-i18n 2>/dev/null || true
    
    GLIBC_VERSION="2.35-r0"
    
    curl -sL -o /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
    
    echo -e "${CYAN}下载 glibc 核心包...${RESET}"
    curl -sL -o /tmp/glibc.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk"
    curl -sL -o /tmp/glibc-bin.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk"
    curl -sL -o /tmp/glibc-i18n.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-i18n-${GLIBC_VERSION}.apk"
    
    for file in glibc.apk glibc-bin.apk glibc-i18n.apk; do
        if [ ! -f "/tmp/$file" ]; then
            echo -e "${RED}$file 下载失败！${RESET}"
            return 1
        fi
    done
    
    echo -e "${CYAN}强制安装 glibc 包 (可能会有警告)...${RESET}"
    apk add --allow-untrusted --force-overwrite /tmp/glibc.apk /tmp/glibc-bin.apk /tmp/glibc-i18n.apk
    
    echo -e "${CYAN}配置语言环境...${RESET}"
    /usr/glibc-compat/bin/localedef -i en_US -f UTF-8 en_US.UTF-8 >/dev/null 2>&1
    rm -f /tmp/glibc*.apk
    
    if [ ! -f "/usr/glibc-compat/lib/ld-linux-x86-64.so.2" ]; then
        echo -e "${RED}glibc 安装验证失败！${RESET}"
        return 1
    fi
    
    echo -e "${CYAN}安装额外兼容包...${RESET}"
    apk add libc6-compat libstdc++ libgcc 2>/dev/null || true
    
    echo -e "${CYAN}持久化环境变量...${RESET}"
    if ! grep -q 'LD_LIBRARY_PATH' /etc/profile; then
        echo 'export LD_LIBRARY_PATH="/usr/glibc-compat/lib:${LD_LIBRARY_PATH}"' >> /etc/profile
    fi
    if ! grep -q 'GLIBC_TUNABLES' /etc/profile; then
        echo 'export GLIBC_TUNABLES=glibc.pthread.rseq=0' >> /etc/profile
    fi
    
    . /etc/profile
    echo -e "${GREEN}依赖包安装完成。${RESET}"
    return 0
}

get_snell_version() {
    SNELL_VERSION="v3.0.0"
    echo -e "${GREEN}使用版本: Snell ${SNELL_VERSION}${RESET}"
}

get_snell_download_url() {
    local arch=$(uname -m)
    if [ "${arch}" = "x86_64" ] || [ "${arch}" = "amd64" ]; then
        echo "https://github.com/llodys/snell/releases/download/v3/alpine-v3.0.0-linux-amd64.zip"
    elif [ "${arch}" = "aarch64" ] || [ "${arch}" = "arm64" ]; then
        echo "https://github.com/llodys/snell/releases/download/v3/alpine-v3.0.0-linux-aarch64.zip"
    else
        echo -e "${RED}错误: 不支持的系统架构: ${arch}。仅支持 amd64 和 aarch64。${RESET}"
        exit 1
    fi
}

get_user_port() {
    echo -e "${CYAN}--------------------------------------------${RESET}"
    while true; do
        printf "请输入 Snell 使用的端口号 (1-65535), 或按回车随机生成: "
        read -r PORT
        if [ -z "$PORT" ]; then
            PORT=$(shuf -i 20000-65000 -n 1)
            echo -e "${YELLOW}已使用随机端口: $PORT${RESET}"
            break
        fi
        case "$PORT" in ''|*[!0-9]*)
            echo -e "${RED}无效输入，请输入纯数字。${RESET}"
            continue
        ;;
        esac
        if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
            echo -e "${GREEN}已选择端口: $PORT${RESET}"
            break
        else
            echo -e "${RED}无效端口号，请输入 1 到 65535 之间的数字。${RESET}"
        fi
    done
}

get_user_psk() {
    echo -e "${CYAN}--------------------------------------------${RESET}"
    echo -e "${YELLOW}设置 PSK${RESET}"
    echo -e "1. 自动随机 PSK (推荐)"
    echo -e "2. 手动输入 PSK"
    printf "请输入选项 [1-2] (默认: 1): "
    read -r psk_choice

    case "$psk_choice" in
        2)
            while true; do
                printf "请输入您的 PSK (建议使用强密码): "
                read -r input_psk
                if [ -z "$input_psk" ]; then
                    echo -e "${RED}PSK 不能为空，请重新输入。${RESET}"
                else
                    PSK="$input_psk"
                    echo -e "${GREEN}已使用手动输入的 PSK。${RESET}"
                    break
                fi
            done
            ;;
        *)
            PSK=$(openssl rand -base64 16)
            echo -e "${GREEN}已自动生成高强度 PSK。${RESET}"
            ;;
    esac
}

open_port() {
    local port=$1
    echo -e "${CYAN}正在配置防火墙 (iptables)...${RESET}"
    iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
    /etc/init.d/iptables save > /dev/null
    rc-update add iptables boot > /dev/null
    echo -e "${GREEN}防火墙端口 ${port} 已开放并设为开机自启。${RESET}"
}

create_management_script() {
    echo -e "${CYAN}正在创建 'snell' 管理命令...${RESET}"
    local SCRIPT_URL="https://raw.githubusercontent.com/llodys/snell/main/snell-alpine.sh"
    
    cat > /usr/local/bin/snell << EOF
#!/bin/sh
RED='\\033[0;31m'; CYAN='\\033[0;36m'; RESET='\\033[0m'
if [ "\$(id -u)" != "0" ]; then echo -e "\${RED}请以 root 权限运行此命令 (e.g., sudo snell)\${RESET}"; exit 1; fi
echo -e "\${CYAN}正在从 GitHub 获取最新的管理脚本...${RESET}"
TMP_SCRIPT=\$(mktemp)
if curl -sL "${SCRIPT_URL}" -o "\$TMP_SCRIPT"; then
    sh "\$TMP_SCRIPT"
    rm -f "\$TMP_SCRIPT"
else
    echo -e "\${RED}下载脚本失败，请检查网络连接。${RESET}"; rm -f "\$TMP_SCRIPT"; exit 1
fi
EOF

    if [ $? -eq 0 ]; then
        chmod +x /usr/local/bin/snell
        echo -e "${GREEN}✓ 'snell' 管理命令创建成功。${RESET}"
        echo -e "${YELLOW}您现在可以在任何地方输入 'sudo snell' 来运行此管理脚本。${RESET}"
    else
        echo -e "${RED}✗ 创建 'snell' 管理命令失败。${RESET}"
    fi
}

show_manual_debug_info() {
    echo -e "${YELLOW}========== 手动调试信息 ==========${RESET}"
    echo -e "${CYAN}请尝试以下命令进行手动调试:${RESET}"
    echo "1. 检查文件类型: file ${INSTALL_DIR}/snell-server"
    echo "2. 检查依赖关系: ldd ${INSTALL_DIR}/snell-server"
    echo "3. 直接运行测试: ${INSTALL_DIR}/snell-server --help"
    echo "4. 使用 glibc 链接器: /usr/glibc-compat/lib/ld-linux-x86-64.so.2 ${INSTALL_DIR}/snell-server --help"
    echo -e "${YELLOW}===================================${RESET}"
}

install_snell() {
    check_root
    
    if [ -f "$OPENRC_SERVICE_FILE" ]; then
        echo -e "${YELLOW}检测到 Snell 已安装，即将执行重装操作...${RESET}"
        rc-service snell stop 2>/dev/null
    fi
    
    install_dependencies
    
    echo -e "${GREEN}已指定安装 Snell${RESET}"
    get_snell_version
    SNELL_URL=$(get_snell_download_url)
    
    echo -e "${CYAN}正在下载 Snell ${SNELL_VERSION}...${RESET}"
    mkdir -p "${INSTALL_DIR}"
    cd /tmp
    curl -L -o snell-server.zip "${SNELL_URL}" || { echo -e "${RED}下载失败!${RESET}"; exit 1; }
    unzip -o snell-server.zip || { echo -e "${RED}解压失败!${RESET}"; exit 1; }
    mv snell-server "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/snell-server"
    rm -f snell-server.zip
    
    echo -e "${CYAN}开始执行兼容性测试...${RESET}"
    export LD_LIBRARY_PATH="/usr/glibc-compat/lib:${LD_LIBRARY_PATH}"
    export GLIBC_TUNABLES="glibc.pthread.rseq=0"

    if timeout 5s ${INSTALL_DIR}/snell-server --help >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 兼容性测试通过：程序可直接运行。${RESET}"
        SNELL_COMMAND="${INSTALL_DIR}/snell-server"
    elif timeout 5s /usr/glibc-compat/lib/ld-linux-x86-64.so.2 ${INSTALL_DIR}/snell-server --help >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 兼容性测试通过：使用 glibc 动态加载器运行。${RESET}"
        cat > ${INSTALL_DIR}/snell-server-wrapper << EOF
#!/bin/sh
export LD_LIBRARY_PATH="/usr/glibc-compat/lib:\${LD_LIBRARY_PATH}"
export GLIBC_TUNABLES="glibc.pthread.rseq=0"
exec /usr/glibc-compat/lib/ld-linux-x86-64.so.2 ${INSTALL_DIR}/snell-server "\$@"
EOF
        chmod +x ${INSTALL_DIR}/snell-server-wrapper
        SNELL_COMMAND="${INSTALL_DIR}/snell-server-wrapper"
    else
        echo -e "${RED}✗ 所有自动测试均失败！${RESET}"
        show_manual_debug_info
        exit 1
    fi

    echo -e "${CYAN}正在创建配置文件和服务...${RESET}"
    mkdir -p "${SNELL_CONF_DIR}/users"
    mkdir -p "/var/log/snell"
    
    get_user_port
    get_user_psk

    cat > ${SNELL_CONF_FILE} << EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = true
tfo = true
version-choice = v3
EOF

    cat > ${OPENRC_SERVICE_FILE} << EOF
#!/sbin/openrc-run

name="Snell Server"
description="Snell proxy server"

command="${SNELL_COMMAND}"
command_args="-c ${SNELL_CONF_FILE}"
command_user="nobody"
command_background="yes"
pidfile="/run/snell.pid"

start_stop_daemon_args="--make-pidfile --stdout /var/log/snell/snell.log --stderr /var/log/snell/snell.log"

depend() {
    need net
    after firewall
}

start_pre() {
    export LD_LIBRARY_PATH="/usr/glibc-compat/lib:\${LD_LIBRARY_PATH}"
    export GLIBC_TUNABLES="glibc.pthread.rseq=0"
    checkpath --directory --owner nobody:nobody --mode 0755 /var/log/snell
    if [ ! -f "${SNELL_CONF_FILE}" ]; then
        eerror "配置文件不存在: ${SNELL_CONF_FILE}"
        return 1
    fi
    if [ ! -x "${SNELL_COMMAND}" ]; then
        eerror "Snell 可执行文件不存在或无执行权限: ${SNELL_COMMAND}"
        return 1
    fi
}

stop_post() {
    [ -f "\${pidfile}" ] && rm -f "\${pidfile}"
}
EOF

    chmod +x ${OPENRC_SERVICE_FILE}

    echo -e "${CYAN}安装/配置完成，正在执行自动重启...${RESET}"
    rc-update add snell default
    
    rc-service snell restart 2>/dev/null
    if [ $? -ne 0 ]; then
        rc-service snell zap >/dev/null 2>&1
        rc-service snell start
    fi

    sleep 2
    if rc-service snell status | grep -q "started"; then
        echo -e "${GREEN}✓ Snell 服务启动成功。${RESET}"
        open_port "$PORT"
        create_management_script
        show_information
    else
        echo -e "${RED}✗ 服务启动后状态异常。${RESET}"
        echo -e "${YELLOW}请查看日志进行排查: tail /var/log/snell/snell.log${RESET}"
    fi
}

uninstall_snell() {
    check_root
    if [ ! -f "$OPENRC_SERVICE_FILE" ]; then
        echo -e "${YELLOW}Snell 未安装。${RESET}"
        return
    fi
    
    echo -e "${CYAN}正在卸载 Snell...${RESET}"
    rc-service snell stop 2>/dev/null
    rc-update del snell default 2>/dev/null
    
    if [ -f "${SNELL_CONF_FILE}" ]; then
        PORT_TO_CLOSE=$(grep 'listen' ${SNELL_CONF_FILE} | cut -d':' -f2 | tr -d ' ')
        if [ -n "$PORT_TO_CLOSE" ]; then
            iptables -D INPUT -p tcp --dport "$PORT_TO_CLOSE" -j ACCEPT 2>/dev/null
        fi
    fi
    
    rm -f ${OPENRC_SERVICE_FILE} ${INSTALL_DIR}/snell ${INSTALL_DIR}/snell-server ${INSTALL_DIR}/snell-server-wrapper
    rm -rf ${SNELL_CONF_DIR} /var/log/snell
    
    echo -e "${GREEN}Snell 已成功卸载。${RESET}"
    exit 0
}

show_information() {
    if [ ! -f "${SNELL_CONF_FILE}" ]; then
        echo -e "${RED}未找到配置文件，请先安装 Snell。${RESET}"
        return
    fi
    
    PORT=$(grep 'listen' ${SNELL_CONF_FILE} | sed 's/.*://')
    PSK=$(grep 'psk' ${SNELL_CONF_FILE} | sed 's/psk\s*=\s*//')
    
    IPV4_ADDR=$(curl -s4 --connect-timeout 5 https://api.ipify.org)
    IPV6_ADDR=$(curl -s6 --connect-timeout 5 https://api64.ipify.org)
    
    echo ""

    echo -e "${YELLOW}配置文件: ${RESET}${SNELL_CONF_FILE}"
    echo -e "${YELLOW}日志文件: ${RESET}/var/log/snell/snell.log"
    echo -e "${BLUE}============================================${RESET}"
    echo -e "${YELLOW}服务器端口: ${RESET}${PORT}"
    echo -e "${YELLOW}PSK 密钥:   ${RESET}${PSK}"
    echo -e "${BLUE}============================================${RESET}"

    if [ -n "$IPV4_ADDR" ] || [ -n "$IPV6_ADDR" ]; then
        echo -e "${YELLOW}Surge 配置格式 (可直接复制)${RESET}"
        
        if [ -n "$IPV4_ADDR" ]; then
            IP_COUNTRY_IPV4=$(curl -s --connect-timeout 5 "http://ipinfo.io/${IPV4_ADDR}/country" 2>/dev/null)
            echo -e "${YELLOW}${IP_COUNTRY_IPV4} = snell, ${IPV4_ADDR}, ${PORT}, psk=${PSK}, version=3, reuse=true, tfo=true${RESET}"
        fi

        if [ -n "$IPV6_ADDR" ]; then
            IP_COUNTRY_IPV6=$(curl -s --connect-timeout 5 "https://ipapi.co/${IPV6_ADDR}/country/" 2>/dev/null)
            echo -e "${YELLOW}${IP_COUNTRY_IPV6} = snell, ${IPV6_ADDR}, ${PORT}, psk=${PSK}, version=3, reuse=true, tfo=true${RESET}"
        fi
    fi
}

restart_snell() {
    check_root
    echo -e "${YELLOW}正在重启 Snell 服务...${RESET}"
    
    rc-service snell restart
    
    if [ $? -ne 0 ]; then
        echo -e "${YELLOW}检测到服务未运行或停止失败，正在尝试强制启动...${RESET}"
        rc-service snell zap >/dev/null 2>&1
        rc-service snell start
    fi

    sleep 2
    if rc-service snell status | grep -q "started"; then
        echo -e "${GREEN}Snell 服务重启/启动成功。${RESET}"
    else
        echo -e "${RED}Snell 服务操作失败。${RESET}"
        echo -e "${YELLOW}请查看日志排查: tail /var/log/snell/snell.log${RESET}"
    fi
}

check_status() {
    check_root
    echo -e "${CYAN}=== Snell 服务状态 ===${RESET}"
    rc-service snell status
    echo -e "\n${CYAN}=== 最新日志 (最后10行) ===${RESET}"
    if [ -f "/var/log/snell/snell.log" ]; then
        tail -10 /var/log/snell/snell.log
    else
        echo "日志文件不存在。"
    fi
}

show_menu() {
    clear
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${CYAN}        Snell for Alpine 管理脚本 v${current_version}${RESET}"
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${GREEN}作者：llodys${RESET}"
    echo -e "${GREEN}仓库：https://github.com/llodys/snell${RESET}"
    echo -e "${CYAN}============================================${RESET}"

    local INSTALL_OPTION_TEXT=""

    if [ -f "$OPENRC_SERVICE_FILE" ]; then
        if rc-service snell status | grep -q "started"; then
            echo -e "服务状态: ${GREEN}运行中${RESET}"
        else
            echo -e "服务状态: ${RED}已停止${RESET}"
        fi
        echo -e "版本状态: ${GREEN}v3.0.0${RESET}"
        INSTALL_OPTION_TEXT="重装 Snell"
    else
        echo -e "服务状态: ${YELLOW}未安装${RESET}"
        INSTALL_OPTION_TEXT="安装 Snell"
    fi
    
    echo -e "${CYAN}--------------------------------------------${RESET}"
    echo -e "${YELLOW}=== 基础功能 ===${RESET}"
    echo -e "${GREEN}1.${RESET} ${INSTALL_OPTION_TEXT}"
    echo -e "${GREEN}2.${RESET} 卸载 Snell"
    echo -e "${GREEN}3.${RESET} 重启服务"
    echo -e "${GREEN}4.${RESET} 查看配置信息"
    echo -e "${CYAN}--------------------------------------------${RESET}"
    echo -e "${YELLOW}=== 管理功能 ===${RESET}"
    echo -e "${GREEN}5.${RESET} 查看详细状态"
    echo -e "${CYAN}--------------------------------------------${RESET}"
    echo -e "${GREEN}0.${RESET} 退出脚本"
    echo -e "${CYAN}============================================${RESET}"
    printf "请输入选项 [0-5]: "
    read -r num
}

main() {
    while true; do
        show_menu
        case "$num" in
            1) install_snell ;;
            2) uninstall_snell ;;
            3) restart_snell ;;
            4) show_information ;;
            5) check_status ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${RESET}"
                exit 0
                ;;
            *)
                echo -e "${RED}请输入正确的选项 [0-5]${RESET}"
                ;;
        esac
        echo ""
        printf "${CYAN}按任意键返回主菜单...${RESET}"
        read -r dummy 
    done
}

check_root
check_system
main
