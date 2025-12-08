#!/bin/bash

#================================================================
# 作者：llodys
# 仓库：https://github.com/llodys/snell
# 描述: 这个脚本用于在 FreeBSD 系统上安装和管理 Snell 代理
#================================================================

# --- 定义颜色代码 ---
RED='\033[0;31m'    # 红色，用于错误信息
GREEN='\033[0;32m'  # 绿色，用于成功信息
YELLOW='\033[0;33m' # 黄色，用于警告或提示信息
CYAN='\033[0;36m'   # 青色，用于状态信息
BLUE='\033[0;34m'   # 蓝色，用于标题
WHITE='\033[0;37m'  # 白色，用于特定文本
RESET='\033[0m'     # 重置颜色

# --- 脚本版本号 ---
current_version="2.0"

# --- 全局变量定义 ---
SCRIPT_DIR="$HOME/app-data"
SCRIPT_PATH="$SCRIPT_DIR/app.sh"
SNELL_EXECUTABLE="$SCRIPT_DIR/bin/core-service"
SNELL_CONFIG="$SCRIPT_DIR/etc/app.json"
SNELL_LOG_FILE="$SCRIPT_DIR/service.log"
DOWNLOAD_URL="https://raw.githubusercontent.com/llodys/snell/main/core-service"

# --- 基础函数 ---
print_info() { echo -e "${GREEN}[信息]${RESET} $1"; }
print_warning() { echo -e "${YELLOW}[警告]${RESET} $1"; }
print_error() { echo -e "${RED}[错误]${RESET} $1"; }
# --- 统一的按键继续函数 ---
press_any_key_to_continue() {
    echo
    read -n 1 -s -r -p "按任意键返回主菜单..."
}

# 检查 Snell 是否已安装
check_installation() {
    [ -f "$SNELL_EXECUTABLE" ]
}

# --- 核心功能函数 ---

# 获取 Snell 程序版本
get_snell_version() {
    if ! check_installation; then
        echo "未知"
        return
    fi
    local version_output
    version_output=$("$SNELL_EXECUTABLE" -v 2>&1)
    local version
    version=$(echo "$version_output" | grep -oE 'v[0-9]+\.[0-9]+\.[0-9]+' | head -n 1)
    if [ -n "$version" ]; then
        echo "$version"
    else
        # 某些版本可能不遵循标准版本输出，提供一个回退值
        echo "v3.0.0"
    fi
}
echo; echo "=================================================="
# 启动 Snell 服务
start_snell() {
    if ! check_installation; then print_error "Snell 未安装，无法启动。"; return 1; fi
    if pgrep -f "$SNELL_EXECUTABLE" > /dev/null; then print_warning "Snell 服务已经在运行中。"; return 0; fi
    print_info "正在启动 Snell 服务..."
    # 启动前清空旧日志
    > "$SNELL_LOG_FILE"
    nohup "$SNELL_EXECUTABLE" -c "$SNELL_CONFIG" > "$SNELL_LOG_FILE" 2>&1 &
    sleep 2
    if pgrep -f "$SNELL_EXECUTABLE" > /dev/null; then
        print_info "✅ 服务已成功启动！"
        return 0
    else
        # [新增] 检查特定的错误类型
        if grep -q "address already in use" "$SNELL_LOG_FILE"; then
            print_error "❌ 端口被占用！"
            return 2 # 返回端口占用错误码
        elif grep -q "bind: operation not permitted" "$SNELL_LOG_FILE"; then
            print_error "❌ 权限错误：此端口未被系统允许使用！"
            print_warning "请确保您使用的端口是通过 Serv00 面板或 'devil' 命令正确申请并分配给您的端口。"
            return 3 # 返回权限错误码
        else
            print_error "❌ 服务启动失败！请使用菜单选项 '6' 查看日志以确定问题。"
            return 1 # 返回通用错误码
        fi
    fi
}

# 停止 Snell 服务
stop_snell() {
    if ! check_installation; then print_error "Snell 未安装，无法停止。"; return 1; fi
    print_info "正在停止 Snell 服务..."
    if pgrep -f "$SNELL_EXECUTABLE" > /dev/null; then
        pkill -f "$SNELL_EXECUTABLE"
        sleep 1
        if pgrep -f "$SNELL_EXECUTABLE" > /dev/null; then
            print_error "❌ 停止服务失败！请尝试手动操作。"
        else
            print_info "✅ 服务已停止。"
        fi
    else
        print_warning "Snell 服务当前未在运行。"
    fi
}

# 重启 Snell 服务
restart_snell() {
    if ! check_installation; then print_error "Snell 未安装，无法重启。"; return 1; fi
    stop_snell
    start_snell
    return $?
}

# 查看配置
display_config() {
    echo; echo "=================================================="; echo
    if ! check_installation; then print_error "Snell 未安装，无法查看配置。"; return 1; fi
    if ! [ -r "$SNELL_CONFIG" ]; then print_error "配置文件不存在: $SNELL_CONFIG"; return; fi
    clear
    echo; echo "=================================================="
    print_info "配置文件 ($SNELL_CONFIG)"
    echo; echo "=================================================="
    cat "$SNELL_CONFIG"
    echo "=================================================="; echo

    # 显示 Surge 格式配置
    print_info "Surge 配置格式 (可直接复制):"
    local ip_addr port psk
    ip_addr=$(curl -s icanhazip.com)
    port=$(grep '^listen\s*=' "$SNELL_CONFIG" | cut -d':' -f2 | xargs)
    psk=$(grep '^psk\s*=' "$SNELL_CONFIG" | cut -d'=' -f2 | xargs)

    if [ -n "$ip_addr" ] && [ -n "$port" ] && [ -n "$psk" ]; then
        # 在 Surge 配置行中也加入 reuse 和 tfo
        echo -e "${GREEN}Snell-Server = snell, $ip_addr, $port, psk=$psk, version=3, reuse=true, tfo=true${RESET}"
    else
        print_warning "未能生成 Surge 配置，请检查配置文件和网络连接。"
    fi
    echo "=================================================="; echo
    
    # 使用青色(CYAN)高亮显示 IP 地址，使其更突出
    echo -e "${GREEN}[信息]${RESET} 您的 IP 地址是: ${CYAN}$ip_addr${RESET}"
    print_info "请根据以上信息在您的客户端中进行配置。"
}

# 查看日志文件
view_log_file() {
    if ! check_installation; then print_error "Snell 未安装，无法查看日志。"; return 1; fi
    if [ -f "$SNELL_LOG_FILE" ]; then
        print_info "显示最近 20 条日志 ($SNELL_LOG_FILE):"
        echo "=================================================="
        tail -n 20 "$SNELL_LOG_FILE"
        echo "=================================================="
    else
        print_warning "日志文件不存在: $SNELL_LOG_FILE"
    fi
}

# --- 开机自启管理功能 ---
enable_autostart() {
    if ! check_installation; then print_error "Snell 未安装，无法操作。"; return 1; fi
    local cron_command="@reboot nohup $SNELL_EXECUTABLE -c $SNELL_CONFIG > $SNELL_LOG_FILE 2>&1 &"
    (crontab -l 2>/dev/null | grep -Fv "$SNELL_EXECUTABLE"; echo "$cron_command") | crontab -
    print_info "✅ 开机自启已开启/更新！"
}

disable_autostart() {
    if ! check_installation; then print_error "Snell 未安装，无法操作。"; return 1; fi
    (crontab -l 2>/dev/null | grep -Fv "$SNELL_EXECUTABLE") | crontab -
    print_info "✅ 开机自启已关闭！"
}

manage_autostart_menu() {
    if ! check_installation; then print_error "Snell 未安装，请先安装服务。"; return 1; fi
    
    while true; do
        clear
        echo -e "${CYAN}============================================${RESET}"
        echo -e "${CYAN}            开机自启管理                     ${RESET}"
        echo -e "${CYAN}============================================${RESET}"
        
        local autostart_option_text=""
        # 检查当前自启状态
        if crontab -l 2>/dev/null | grep -q "$SNELL_EXECUTABLE"; then
            echo -e "当前状态: ${GREEN}已开启${RESET}"
            autostart_option_text="更新"
        else
            echo -e "当前状态: ${RED}已关闭${RESET}"
            autostart_option_text="开启"
        fi

        echo -e "${CYAN}--------------------------------------------${RESET}"
        echo -e "${GREEN}1.${RESET} ${autostart_option_text}"
        echo -e "${GREEN}2.${RESET} 关闭"
        echo
        echo -e "${GREEN}0.${RESET} 返回主菜单"
        echo -e "${CYAN}============================================${RESET}"

        read -p "请输入选项 [0-2]: " choice
        case "$choice" in
            1)
                enable_autostart
                read -n 1 -s -r -p "操作完成，按任意键继续..."
                ;;
            2)
                disable_autostart
                read -n 1 -s -r -p "操作完成，按任意键继续..."
                ;;
            0)
                break # 退出子菜单循环
                ;;
            *)
                print_warning "无效输入。"
                read -n 1 -s -r -p "按任意键继续..."
                ;;
        esac
    done
}

auto_get_port_with_devil() {
    local requested_port=$1
    print_info "正在尝试使用 'devil' 命令申请指定 TCP 端口: $requested_port..." >&2
    local command_to_run="devil port add tcp $requested_port"
    local output
    output=$(eval "$command_to_run" 2>&1)
    if [ $? -eq 0 ]; then
        print_info "✅ 成功保留端口: $requested_port" >&2
        echo "$requested_port"
        return 0
    else
        print_error "'$command_to_run' 命令执行失败。" >&2
        print_error "错误信息: $output" >&2
        return 1
    fi
}

# 安装 Snell 服务
run_installation() {
    echo
    if check_installation; then
        print_warning "检测到已安装Snell，继续操作将覆盖现有配置！"
        read -p "是否继续? (y/n): " confirm
        if [[ ! "$confirm" =~ ^[yY]$ ]]; then print_info "操作已取消。"; return; fi
    fi

    if [ ! -f "$SNELL_EXECUTABLE" ]; then
        print_info "首次安装，正在下载 Snell 程序..."
        mkdir -p "$SCRIPT_DIR/bin" "$SCRIPT_DIR/etc"
        if curl -L -s "$DOWNLOAD_URL" -o "$SNELL_EXECUTABLE" && chmod +x "$SNELL_EXECUTABLE"; then
            print_info "下载成功。"
        else
            print_error "下载失败！请检查网络或链接是否有效。"
            rm -f "$SNELL_EXECUTABLE"
            return 1
        fi
    fi

    while true; do
        local LISTEN_PORT=""
        local use_devil="n"
        if command -v devil &> /dev/null; then
            read -p "检测到 'devil' 命令，是否使用它来申请端口? (y/n, 默认 n): " use_devil
            use_devil=${use_devil:-n}
            if [[ "$use_devil" =~ ^[yY]$ ]]; then
                local specific_port
                while true; do
                    read -p "请输入您想申请的端口号 (1025-65535): " specific_port
                    if [[ "$specific_port" =~ ^[0-9]+$ ]] && [ "$specific_port" -gt 1024 ] && [ "$specific_port" -le 65535 ]; then
                        break
                    else
                        print_warning "输入无效！请输入一个 1025 到 65535 之间的数字。"
                    fi
                done
                LISTEN_PORT=$(auto_get_port_with_devil "$specific_port")
            fi
        fi

        if [ -z "$LISTEN_PORT" ]; then
            if [[ "$use_devil" =~ ^[yY]$ ]]; then
                print_warning "通过 devil 申请端口失败，请转为手动输入。"
            fi
            print_warning "请确保您已在 Serv00 面板的 'Porty' 中获取了端口。"
            while true; do
                read -p "请输入 Serv00 为您分配的端口号: " manual_port
                if [[ "$manual_port" =~ ^[0-9]+$ ]] && [ "$manual_port" -gt 1024 ]; then
                    LISTEN_PORT=$manual_port
                    break
                else
                    print_warning "输入无效！"
                fi
            done
        fi

        print_info "好的，将使用端口:$LISTEN_PORT"
        PSK=$(openssl rand -base64 24)
        
        {
            echo "[snell-server]"
            echo "listen = 0.0.0.0:$LISTEN_PORT"
            echo "psk = $PSK"
            echo "reuse = true"
            echo "tfo = true"
        } > "$SNELL_CONFIG"

        print_info "正在测试配置并启动服务..."
        start_snell
        local start_result=$?

        if [[ $start_result -eq 0 ]]; then
            break
        elif [[ $start_result -eq 2 || $start_result -eq 3 ]]; then
            print_warning "端口 $LISTEN_PORT 无法使用，请尝试其他端口。"
            echo
        else
            print_error "发生未知错误，安装中止。"
            return 1
        fi
    done

    print_info "配置完成，安装成功！"
    sleep 1
    display_config
    
    print_info "正在自动设置开机自启..."
    enable_autostart
}

# 卸载服务
run_uninstall() {
    if ! check_installation; then print_error "Snell 未安装，无需卸载。"; return 1; fi
    read -p "这将彻底删除 Snell 所有文件和配置，确定吗? (y/n): " confirm
    if [[ ! "$confirm" =~ ^[yY]$ ]]; then print_info "操作已取消。"; return; fi
    
    stop_snell

    if [ -f "$SNELL_CONFIG" ] && command -v devil &> /dev/null; then
        local PORT_TO_DEL=$(grep '^listen\s*=' "$SNELL_CONFIG" | cut -d':' -f2 | xargs)
        if [[ "$PORT_TO_DEL" =~ ^[0-9]+$ ]]; then
            print_info "正在尝试使用 'devil' 命令删除端口: $PORT_TO_DEL..."
            devil port del tcp "$PORT_TO_DEL"
        fi
    fi

    print_info "正在删除开机自启..."
    disable_autostart
    
    print_info "正在删除脚本和配置文件..."
    rm -rf "$SCRIPT_DIR"
    
    print_info "✅ Snell 已被成功卸载。"
    echo -e "${GREEN}感谢使用，再见！${RESET}"
    exit 0
}

# 主菜单
show_main_menu() {
    while true; do
        clear
        echo -e "${CYAN}============================================${RESET}"
        echo -e "${CYAN}       Snell for FreeBSD 管理脚本 v${current_version}${RESET}"
        echo -e "${CYAN}============================================${RESET}"
        echo -e "${GREEN}作者：llodys${RESET}"
        echo -e "${GREEN}仓库：https://github.com/llodys/snell${RESET}"
        echo -e "${CYAN}============================================${RESET}"

        if check_installation; then
            if pgrep -f "$SNELL_EXECUTABLE" > /dev/null; then
                echo -e "服务状态: ${GREEN}运行中${RESET}"
            else
                echo -e "服务状态: ${RED}已停止${RESET}"
            fi
            local version
            version=$(get_snell_version)
            echo -e "版本状态: ${GREEN}${version}${RESET}"
        else
            echo -e "服务状态: ${YELLOW}未安装${RESET}"
        fi
        
        echo -e "${CYAN}--------------------------------------------${RESET}"

        local install_option_text="安装 Snell"
        if check_installation; then install_option_text="重装 Snell"; fi
        
        echo -e "${YELLOW}=== 基础功能 ===${RESET}"
        echo -e "${GREEN}1.${RESET} ${install_option_text}"
        echo -e "${GREEN}2.${RESET} 卸载 Snell"
        echo -e "${GREEN}3.${RESET} 重启服务"
        echo -e "${GREEN}4.${RESET} 查看配置信息"
        echo -e "${CYAN}--------------------------------------------${RESET}"
        echo -e "${YELLOW}=== 管理功能 ===${RESET}"
        echo -e "${GREEN}5.${RESET} 开机自启管理"
        echo -e "${GREEN}6.${RESET} 查看详细状态"
        echo -e "${CYAN}--------------------------------------------${RESET}"
        echo -e "${GREEN}0.${RESET} 退出脚本"
        echo -e "${CYAN}============================================${RESET}"
        
        read -p "请输入选项 [0-6]: " choice

        case "$choice" in
            1)
                run_installation
                press_any_key_to_continue
                ;;
            2)
                run_uninstall
                ;;
            3)
                restart_snell
                press_any_key_to_continue
                ;;
            4)
                display_config
                press_any_key_to_continue
                ;;
            5)
                manage_autostart_menu
                # 子菜单处理自己的逻辑，这里不需要暂停
                ;;
            6)
                view_log_file
                press_any_key_to_continue
                ;;
            0)
                echo -e "${GREEN}感谢使用，再见！${RESET}"
                exit 0
                ;;
            *)
                print_warning "无效输入。"
                press_any_key_to_continue
                ;;
        esac
    done
}

# --- 脚本主入口 ---
if [ ! -f "$SCRIPT_PATH" ] && [ "$(basename "$0")" = "bash" ]; then
    print_info "首次运行，正在将脚本自身保存到 $SCRIPT_PATH ..."
    mkdir -p "$SCRIPT_DIR"; cat > "$SCRIPT_PATH"; chmod +x "$SCRIPT_PATH"
    print_info "保存成功。正在从本地文件重新启动脚本..."; echo "----------------------------------------------------"
    exec "$SCRIPT_PATH" "$@"
fi

if ! command -v curl &> /dev/null || ! command -v openssl &> /dev/null; then
    print_error "错误：本脚本需要 'curl'和 'openssl'，请先确保它们已安装。"
    exit 1
fi

show_main_menu
