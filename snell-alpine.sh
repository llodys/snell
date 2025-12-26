#!/bin/sh
# ================================================================
# 作者：llodys
# 仓库：https://github.com/llodys/snell
# 描述: 此脚本用于在 Alpine Linux 系统上安装和管理 Snell 代理服务。
# ================================================================

# --- 定义颜色代码 ---
RED='\033[0;31m'    # 红色，用于错误信息
GREEN='\033[0;32m'  # 绿色，用于成功信息
YELLOW='\033[0;33m' # 黄色，用于警告或提示信息
CYAN='\033[0;36m'   # 青色，用于状态信息
BLUE='\033[0;34m'   # 蓝色，用于标题
WHITE='\033[0;37m'  # 白色，用于特定文本
RESET='\033[0m'     # 重置颜色

# 脚本自身的版本号
current_version="2.0"

# 用于存储 Snell 的版本号 (硬编码为 v3.0.0)
SNELL_VERSION=""
# 用于存储 Snell 服务最终的启动命令 (考虑到兼容性问题，可能是直接启动或通过 wrapper 启动)
SNELL_COMMAND=""

# --- 核心路径定义 ---
INSTALL_DIR="/usr/local/bin"
SNELL_CONF_DIR="/etc/snell"
SNELL_CONF_FILE="${SNELL_CONF_DIR}/users/snell-main.conf"
OPENRC_SERVICE_FILE="/etc/init.d/snell"

# --- 基础辅助函数 ---
check_root() {
    if [ "$(id -u)" != "0" ]; then
        echo -e "${RED}错误: 请以 root 权限运行此脚本。${RESET}"
        exit 1
    fi
}

# 检查操作系统是否为 Alpine Linux
check_system() {
    if [ ! -f /etc/alpine-release ]; then
        echo -e "${RED}错误: 此脚本仅适用于 Alpine Linux 系统${RESET}"
        exit 1
    fi
}

# --- 核心安装与配置函数 ---
# 安装运行 Snell 所需的依赖包
# Alpine 默认使用 musl libc，而 Snell 官方二进制文件基于 glibc 编译，
# 因此需要安装一个 glibc 兼容层。
install_dependencies() {
    echo -e "${CYAN}正在更新软件源并安装基础依赖...${RESET}"
    apk update
    apk add curl wget unzip openssl iptables openrc net-tools file
    
    echo -e "${CYAN}正在为 Alpine 安装 glibc 兼容环境...${RESET}"
    
    # 安装 gcompat 包，提供基础的 glibc 兼容性
    apk add gcompat
    
    # 清理可能已存在的旧版 glibc 包，避免冲突
    apk del glibc glibc-bin glibc-i18n 2>/dev/null || true
    
    # 指定要安装的 glibc 包版本
    GLIBC_VERSION="2.35-r0"
    
    # 下载 glibc 包作者的公钥
    curl -sL -o /etc/apk/keys/sgerrand.rsa.pub https://alpine-pkgs.sgerrand.com/sgerrand.rsa.pub
    
    # 从 GitHub 下载 glibc 的三个核心 apk 包
    echo -e "${CYAN}下载 glibc 核心包...${RESET}"
    curl -sL -o /tmp/glibc.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-${GLIBC_VERSION}.apk"
    curl -sL -o /tmp/glibc-bin.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-bin-${GLIBC_VERSION}.apk"
    curl -sL -o /tmp/glibc-i18n.apk "https://github.com/sgerrand/alpine-pkg-glibc/releases/download/${GLIBC_VERSION}/glibc-i18n-${GLIBC_VERSION}.apk"
    
    # 检查所有包是否下载成功
    for file in glibc.apk glibc-bin.apk glibc-i18n.apk; do
        if [ ! -f "/tmp/$file" ]; then
            echo -e "${RED}$file 下载失败！${RESET}"
            return 1
        fi
    done
    
    # 强制安装下载的 glibc 包
    echo -e "${CYAN}强制安装 glibc 包 (可能会有警告)...${RESET}"
    apk add --allow-untrusted --force-overwrite /tmp/glibc.apk /tmp/glibc-bin.apk /tmp/glibc-i18n.apk
    
    # 配置本地化环境
    echo -e "${CYAN}配置语言环境...${RESET}"
    /usr/glibc-compat/bin/localedef -i en_US -f UTF-8 en_US.UTF-8 >/dev/null 2>&1
    
    # 清理临时文件
    rm -f /tmp/glibc*.apk
    
    # 验证 glibc 动态链接库是否存在，确保安装成功
    if [ ! -f "/usr/glibc-compat/lib/ld-linux-x86-64.so.2" ]; then
        echo -e "${RED}glibc 安装验证失败！${RESET}"
        return 1
    fi
    
    # 安装其他兼容性库
    echo -e "${CYAN}安装额外兼容包...${RESET}"
    apk add libc6-compat libstdc++ libgcc 2>/dev/null || true
    
    # 将 glibc 库的路径添加到系统环境变量，以便程序可以找到它
    echo -e "${CYAN}持久化环境变量...${RESET}"
    if ! grep -q 'LD_LIBRARY_PATH' /etc/profile; then
        echo 'export LD_LIBRARY_PATH="/usr/glibc-compat/lib:${LD_LIBRARY_PATH}"' >> /etc/profile
    fi
    if ! grep -q 'GLIBC_TUNABLES' /etc/profile; then
        echo 'export GLIBC_TUNABLES=glibc.pthread.rseq=0' >> /etc/profile
    fi
    
    # 使环境变量在当前会话中立即生效
    . /etc/profile
    
    echo -e "${GREEN}依赖包安装完成。${RESET}"
    return 0
}

# 获取 Snell 版本号
get_snell_version() {
    SNELL_VERSION="v3.0.0"
    echo -e "${GREEN}使用版本: Snell ${SNELL_VERSION}${RESET}"
}

# 获取 Snell v3 的下载链接 (仅支持 amd64/x86_64 架构)
get_snell_download_url() {
    local arch=$(uname -m)
    if [ "${arch}" = "x86_64" ] || [ "${arch}" = "amd64" ]; then
        echo "https://github.com/llodys/snell/releases/download/v3/alpine-v3.0.0-linux-amd64.zip"
    else
        echo -e "${RED}错误: 此 Snell 脚本仅支持 amd64/x86_64 架构。${RESET}"
        exit 1
    fi
}

# 提示用户输入端口号，若不输入则随机生成
get_user_port() {
    while true; do
        printf "请输入 Snell 使用的端口号 (1-65535), 或按回车随机生成: "
        read -r PORT
        if [ -z "$PORT" ]; then
            PORT=$(shuf -i 20000-65000 -n 1)
            echo -e "${YELLOW}已使用随机端口: $PORT${RESET}"
            break
        fi
        # 验证输入是否为纯数字
        case "$PORT" in ''|*[!0-9]*)
            echo -e "${RED}无效输入，请输入纯数字。${RESET}"
            continue
        ;;
        esac
        # 验证端口号是否在有效范围内
        if [ "$PORT" -ge 1 ] && [ "$PORT" -le 65535 ]; then
            echo -e "${GREEN}已选择端口: $PORT${RESET}"
            break
        else
            echo -e "${RED}无效端口号，请输入 1 到 65535 之间的数字。${RESET}"
        fi
    done
}

# 使用 iptables 开放指定端口并设置开机自启
open_port() {
    local port=$1
    echo -e "${CYAN}正在配置防火墙 (iptables)...${RESET}"
    iptables -I INPUT 1 -p tcp --dport "$port" -j ACCEPT
    /etc/init.d/iptables save > /dev/null
    rc-update add iptables boot > /dev/null
    echo -e "${GREEN}防火墙端口 ${port} 已开放并设为开机自启。${RESET}"
}

# 创建一个名为 'snell' 的快捷管理命令
# 这个命令本质上是一个包装器，每次执行时都会从 GitHub 下载并运行最新的脚本
create_management_script() {
    echo -e "${CYAN}正在创建 'snell' 管理命令...${RESET}"
    local SCRIPT_URL="https://raw.githubusercontent.com/llodys/snell/main/snell-alpine.sh"
    
    # 使用 cat 和 heredoc 创建脚本文件
    cat > /usr/local/bin/snell << EOF
#!/bin/sh
# Snell 管理命令包装器
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

    # 赋予快捷命令可执行权限
    if [ $? -eq 0 ]; then
        chmod +x /usr/local/bin/snell
        echo -e "${GREEN}✓ 'snell' 管理命令创建成功。${RESET}"
        echo -e "${YELLOW}您现在可以在任何地方输入 'sudo snell' 来运行此管理脚本。${RESET}"
    else
        echo -e "${RED}✗ 创建 'snell' 管理命令失败。${RESET}"
    fi
}

# 当自动兼容性测试失败时，显示此信息以供手动调试
show_manual_debug_info() {
    echo -e "${YELLOW}========== 手动调试信息 ==========${RESET}"
    echo -e "${CYAN}请尝试以下命令进行手动调试:${RESET}"
    echo "1. 检查文件类型: file ${INSTALL_DIR}/snell-server"
    echo "2. 检查依赖关系: ldd ${INSTALL_DIR}/snell-server"
    echo "3. 直接运行测试: ${INSTALL_DIR}/snell-server --help"
    echo "4. 使用 glibc 链接器: /usr/glibc-compat/lib/ld-linux-x86-64.so.2 ${INSTALL_DIR}/snell-server --help"
    echo -e "${YELLOW}===================================${RESET}"
}

# 主安装函数，执行安装 Snell 的所有步骤
install_snell() {
    check_root
    # 检查是否已安装，避免重复安装
    if [ -f "$OPENRC_SERVICE_FILE" ]; then
        echo -e "${YELLOW}Snell 已安装，如需重装请先卸载。${RESET}"
        return
    fi
    
    # 1. 安装依赖
    install_dependencies
    
    # 2. 获取版本和下载链接 (已硬编码为 v3)
    echo -e "${GREEN}已指定安装 Snell${RESET}"
    get_snell_version
    SNELL_URL=$(get_snell_download_url)
    
    # 3. 下载和解压
    echo -e "${CYAN}正在下载 Snell ${SNELL_VERSION}...${RESET}"
    mkdir -p "${INSTALL_DIR}"
    cd /tmp
    curl -L -o snell-server.zip "${SNELL_URL}" || { echo -e "${RED}下载失败!${RESET}"; exit 1; }
    unzip -o snell-server.zip || { echo -e "${RED}解压失败!${RESET}"; exit 1; }
    mv snell-server "${INSTALL_DIR}/"
    chmod +x "${INSTALL_DIR}/snell-server"
    rm -f snell-server.zip
    
    # 4. 兼容性测试
    echo -e "${CYAN}开始执行兼容性测试...${RESET}"
    export LD_LIBRARY_PATH="/usr/glibc-compat/lib:${LD_LIBRARY_PATH}"
    export GLIBC_TUNABLES="glibc.pthread.rseq=0"

    # 尝试直接运行 snell-server
    if timeout 5s ${INSTALL_DIR}/snell-server --help >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 兼容性测试通过：程序可直接运行。${RESET}"
        SNELL_COMMAND="${INSTALL_DIR}/snell-server"
    # 如果直接运行失败，尝试使用 glibc 的动态链接器来启动
    elif timeout 5s /usr/glibc-compat/lib/ld-linux-x86-64.so.2 ${INSTALL_DIR}/snell-server --help >/dev/null 2>&1; then
        echo -e "${GREEN}✓ 兼容性测试通过：使用 glibc 动态加载器运行。${RESET}"
        # 创建一个包装脚本来简化启动命令
        cat > ${INSTALL_DIR}/snell-server-wrapper << EOF
#!/bin/sh
export LD_LIBRARY_PATH="/usr/glibc-compat/lib:\${LD_LIBRARY_PATH}"
export GLIBC_TUNABLES="glibc.pthread.rseq=0"
exec /usr/glibc-compat/lib/ld-linux-x86-64.so.2 ${INSTALL_DIR}/snell-server "\$@"
EOF
        chmod +x ${INSTALL_DIR}/snell-server-wrapper
        SNELL_COMMAND="${INSTALL_DIR}/snell-server-wrapper"
    else
        # 如果两种方式都失败，则报错退出
        echo -e "${RED}✗ 所有自动测试均失败！${RESET}"
        show_manual_debug_info
        exit 1
    fi

    # 5. 创建配置文件和服务
    echo -e "${CYAN}正在创建配置文件和服务...${RESET}"
    mkdir -p "${SNELL_CONF_DIR}/users"
    mkdir -p "/var/log/snell"
    get_user_port
    PSK=$(openssl rand -base64 16) # 随机生成 PSK 密钥

    # 写入主配置文件
    cat > ${SNELL_CONF_FILE} << EOF
[snell-server]
listen = 0.0.0.0:${PORT}
psk = ${PSK}
ipv6 = true
tfo = true
version-choice = v3
EOF

    # 写入 OpenRC 服务文件
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

    # 赋予服务脚本可执行权限
    chmod +x ${OPENRC_SERVICE_FILE}

    # 6. 启动服务并检查状态
    echo -e "${CYAN}正在启动 Snell 服务...${RESET}"
    rc-update add snell default # 添加到开机自启
    rc-service snell start      # 启动服务

    sleep 2 # 等待服务启动
    if rc-service snell status | grep -q "started"; then
        echo -e "${GREEN}✓ Snell 服务运行正常。${RESET}"
        open_port "$PORT"
        create_management_script
        show_information
    else
        echo -e "${RED}✗ 服务启动后状态异常。${RESET}"
        echo -e "${YELLOW}请查看日志进行排查: tail /var/log/snell/snell.log${RESET}"
    fi
}

# 卸载 Snell 服务
uninstall_snell() {
    check_root
    if [ ! -f "$OPENRC_SERVICE_FILE" ]; then
        echo -e "${YELLOW}Snell 未安装。${RESET}"
        return
    fi
    
    echo -e "${CYAN}正在卸载 Snell...${RESET}"
    # 停止服务并移除开机自启
    rc-service snell stop 2>/dev/null
    rc-update del snell default 2>/dev/null
    
    # 从防火墙中删除端口规则
    if [ -f "${SNELL_CONF_FILE}" ]; then
        PORT_TO_CLOSE=$(grep 'listen' ${SNELL_CONF_FILE} | cut -d':' -f2 | tr -d ' ')
        if [ -n "$PORT_TO_CLOSE" ]; then
            iptables -D INPUT -p tcp --dport "$PORT_TO_CLOSE" -j ACCEPT 2>/dev/null
        fi
    fi
    
    # 删除所有相关文件和目录
    rm -f ${OPENRC_SERVICE_FILE} ${INSTALL_DIR}/snell-server ${INSTALL_DIR}/snell-server-wrapper
    rm -rf ${SNELL_CONF_DIR} /var/log/snell
    
    echo -e "${GREEN}Snell 已成功卸载。${RESET}"
}

# 显示配置信息
show_information() {
    if [ ! -f "${SNELL_CONF_FILE}" ]; then
        echo -e "${RED}未找到配置文件，请先安装 Snell。${RESET}"
        return
    fi
    
    # 从配置文件中解析端口和 PSK
    PORT=$(grep 'listen' ${SNELL_CONF_FILE} | sed 's/.*://')
    PSK=$(grep 'psk' ${SNELL_CONF_FILE} | sed 's/psk\s*=\s*//')
    
    # 获取公网 IP 地址
    IPV4_ADDR=$(curl -s4 --connect-timeout 5 https://api.ipify.org)
    IPV6_ADDR=$(curl -s6 --connect-timeout 5 https://api64.ipify.org)
    
    # 根据用户要求，移除此处的 clear 命令
    # clear 
    echo "" # 添加一个空行以分隔主菜单和输出信息

    # 按照用户指定的格式显示信息
    echo -e "${YELLOW}配置文件: ${RESET}${SNELL_CONF_FILE}"
    echo -e "${YELLOW}日志文件: ${RESET}/var/log/snell/snell.log"
    echo -e "${BLUE}============================================${RESET}"
    echo -e "${YELLOW}服务器端口: ${RESET}${PORT}"
    echo -e "${YELLOW}PSK 密钥:   ${RESET}${PSK}"
    echo -e "${BLUE}============================================${RESET}"

    # 检查是否存在公网IP，如果存在，则显示 Surge 配置部分
    if [ -n "$IPV4_ADDR" ] || [ -n "$IPV6_ADDR" ]; then
        echo -e "${YELLOW}Surge 配置格式 (可直接复制)${RESET}"
        
        # 显示 IPv4 配置
        if [ -n "$IPV4_ADDR" ]; then
            IP_COUNTRY_IPV4=$(curl -s --connect-timeout 5 "http://ipinfo.io/${IPV4_ADDR}/country" 2>/dev/null)
            echo -e "${YELLOW}${IP_COUNTRY_IPV4} = snell, ${IPV4_ADDR}, ${PORT}, psk=${PSK}, version=3, reuse=true, tfo=true${RESET}"
        fi

        # 显示 IPv6 配置
        if [ -n "$IPV6_ADDR" ]; then
            IP_COUNTRY_IPV6=$(curl -s --connect-timeout 5 "https://ipapi.co/${IPV6_ADDR}/country/" 2>/dev/null)
            echo -e "${YELLOW}${IP_COUNTRY_IPV6} = snell, ${IPV6_ADDR}, ${PORT}, psk=${PSK}, version=3, reuse=true, tfo=true${RESET}"
        fi
    fi
}

# 重启 Snell 服务
restart_snell() {
    check_root
    echo -e "${YELLOW}正在重启 Snell 服务...${RESET}"
    rc-service snell restart
    sleep 2
    if rc-service snell status | grep -q "started"; then
        echo -e "${GREEN}Snell 服务重启成功。${RESET}"
    else
        echo -e "${RED}Snell 服务重启失败。${RESET}"
    fi
}

# 查看服务状态和日志
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

# 主菜单
show_menu() {
    clear
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${CYAN}        Snell for Alpine 管理脚本 v${current_version}${RESET}"
    echo -e "${CYAN}============================================${RESET}"
    echo -e "${GREEN}作者：llodys${RESET}"
    echo -e "${GREEN}仓库：https://github.com/llodys/snell${RESET}"
    echo -e "${CYAN}============================================${RESET}"

    # 检查服务状态并显示
    if [ -f "$OPENRC_SERVICE_FILE" ]; then
        if rc-service snell status | grep -q "started"; then
            echo -e "服务状态: ${GREEN}运行中${RESET}"
        else
            echo -e "服务状态: ${RED}已停止${RESET}"
        fi
        # 新增：显示版本状态
        echo -e "版本状态: ${GREEN}v3.0.0${RESET}"
    else
        echo -e "服务状态: ${YELLOW}未安装${RESET}"
    fi
    
    # 显示菜单选项 (根据用户之前的要求进行布局)
    echo -e "${CYAN}--------------------------------------------${RESET}"
    echo -e "${YELLOW}=== 基础功能 ===${RESET}"
    echo -e "${GREEN}1.${RESET} 安装 Snell"
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

# 脚本主函数
main() {
    # 持续循环显示菜单，直到用户选择退出
    while true; do
        show_menu
        # 根据用户输入执行相应的功能
        case "$num" in
            1) install_snell ;;
            2) uninstall_snell ;;
            3) restart_snell ;;   # Bug 已修复
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
        read -r dummy # 等待用户按键，提供更好的交互体验
    done
}

# 首先检查 root 权限和系统类型
check_root
check_system

# 调用主函数
main
