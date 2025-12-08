#!/usr/bin/bash

# ==============================================================================
#                      DANGER: ACCOUNT RESET SCRIPT
# 
# This script will permanently delete all websites, ports, and files
# associated with the user account. This action is IRREVERSIBLE.
# ==============================================================================

# --- Style and Sound Definitions ---
# Background Red: \033[41m, Bold White: \033[1;97m
# Bold Red: \033[1;31m, Bold Yellow: \033[1;33m
TITLE_STYLE='\033[1;97;41m'
BODY_STYLE='\033[1;31m'
PROMPT_STYLE='\033[1;33m'
NC='\033[0m'      # No Color / Reset
BELL='\a'         # Terminal Bell

# --- Function Definitions ---

# Deletes all configured domains
delete_all_domains() {
    domain_list=$(devil www list | awk 'NR>2 {print $1}')
    if [ -z "$domain_list" ]; then
        echo "没有找到任何域名。"
        return
    fi
    for domain in $domain_list; do
        echo "正在删除域名: $domain"
        devil www del "$domain"
    done
}

# Deletes all configured ports
delete_all_ports() {
    port_list=$(devil port list | awk 'NR>2 {print $1, $2}')
    if [ -z "$port_list" ]; then
        echo "没有找到任何端口。"
        return
    fi
    while read -r port type; do
        if [ -n "$port" ] && [ -n "$type" ]; then
            echo "正在删除端口: $type $port"
            devil port del "$type" "$port"
        fi
    done <<< "$port_list"
}

# Deletes all user files and logs out the user
reset_user() {
    echo "正在删除用户家目录下的所有文件..."
    # Use the safer 'find' command to delete all contents of the home directory
    find ~ -mindepth 1 -delete
    
    echo "文件删除完成。"
    echo "正在重置语言并终止会话..."
    devil lang set english
    killall -u $(whoami)
}


# --- Main Execution Flow ---

# Step 1: Display the security confirmation prompt
echo -e "${BELL}"
echo ""
echo -e "${TITLE_STYLE} █████████████████████████ 警 告 ██████████████████████████ ${NC}"
echo ""
echo -e "${BODY_STYLE}   此操作具有毁灭性，将永久删除账户下的所有数据：${NC}"
echo -e "${BODY_STYLE}   - 全部网站 (All Domains)${NC}"
echo -e "${BODY_STYLE}   - 全部端口 (All Ports)${NC}"
echo -e "${BODY_STYLE}   - 全部文件 (All Files)${NC}"
echo ""
echo -e "${BODY_STYLE}   数据一经删除，无法恢复。${NC}"
echo ""
echo -e "${TITLE_STYLE} ████████████████████████████████████████████████████████████ ${NC}"
echo ""
# Using printf to avoid color issues with the read prompt
printf "${PROMPT_STYLE}► 请输入 'yes' 以确认执行此操作: ${NC}"
read confirmation

# Step 2: Validate the confirmation
if [ "$confirmation" != "yes" ]; then
    echo ""
    echo "操作已取消。"
    exit 0
fi

# Step 3: Final warning and countdown
echo ""
echo "最终确认成功，毁灭性操作将在 5 秒后开始..."
sleep 5

# Step 4: Execute the reset sequence
echo ""
echo "--- [1/3] 开始删除所有域名 ---"
delete_all_domains
echo "--- 域名删除完毕 ---"
echo ""

echo "--- [2/3] 开始删除所有端口 ---"
delete_all_ports
echo "--- 端口删除完毕 ---"
echo ""

echo "--- [3/3] 开始重置用户数据 ---"
reset_user

echo "脚本执行完毕。"
