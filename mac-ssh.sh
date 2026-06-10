stty sane
sudo rm -f /usr/local/bin/s

cat > ~/ssh_tool_color <<'EOF'
#!/bin/zsh
# SSH 快捷管理工具
# 首次运行/配置缺失 自动强制写入完整 Host * 全局配置（全套固定规则+心跳保活）
VERSION="v2.8-final"
SCRIPT_PATH="/usr/local/bin/s"
UPDATE_URL="https://raw.githubusercontent.com/lg10/mac-ssh/refs/heads/main/mac-ssh.sh"
PLUGIN_CONF="$HOME/.ssh_color_plugin"

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m'

SSH_CONFIG="$HOME/.ssh/config"
SSH_DIR="$HOME/.ssh"
KEYS_DIR="$SSH_DIR/keys"
setopt NO_GLOB_SUBST

trap 'stty sane; exit' EXIT INT QUIT TERM

# 初始化：目录 + 权限 + 强制补全整套全局 Host * 配置
init_env() {
    # 创建目录并设置权限
    mkdir -p "$SSH_DIR" "$KEYS_DIR"
    chmod 700 "$SSH_DIR" "$KEYS_DIR"
    [[ ! -f "$SSH_CONFIG" ]] && touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"

    # 逐条校验全局配置，缺任意一条就重建整个 Host * 区块
    local need_rebuild=0
    grep -q "AddKeysToAgent yes"       "$SSH_CONFIG" || need_rebuild=1
    grep -q "UseKeychain yes"          "$SSH_CONFIG" || need_rebuild=1
    grep -q "StrictHostKeyChecking no" "$SSH_CONFIG" || need_rebuild=1
    grep -q "RequestTTY force"        "$SSH_CONFIG" || need_rebuild=1
    grep -q "ServerAliveInterval 30"  "$SSH_CONFIG" || need_rebuild=1
    grep -q "ServerAliveCountMax 3"   "$SSH_CONFIG" || need_rebuild=1

    if [[ $need_rebuild -eq 1 ]]; then
        local tmp=$(mktemp)
        local skip_global=0

        # 过滤删除原有 Host * 区块，保留所有自定义主机配置
        while IFS= read -r line || [[ -n "$line" ]]; do
            if [[ $line =~ ^[[:space:]]*Host[[:space:]]+\* ]]; then
                skip_global=1
                continue
            fi
            # 遇到下一个普通 Host，结束全局区块跳过
            if [[ $skip_global -eq 1 && $line =~ ^[[:space:]]*Host[[:space:]]+[^*] ]]; then
                skip_global=0
            fi
            if [[ $skip_global -eq 0 ]]; then
                echo "$line" >> "$tmp"
            fi
        done < "$SSH_CONFIG"

        # 写入你固定的全套全局配置
        echo "Host *" >> "$tmp"
        echo "    AddKeysToAgent yes" >> "$tmp"
        echo "    UseKeychain yes" >> "$tmp"
        echo "    StrictHostKeyChecking no" >> "$tmp"
        echo "    RequestTTY force" >> "$tmp"
        echo "    ServerAliveInterval 30" >> "$tmp"
        echo "    ServerAliveCountMax 3" >> "$tmp"
        echo "" >> "$tmp"

        # 覆盖原配置文件
        mv "$tmp" "$SSH_CONFIG"
        chmod 600 "$SSH_CONFIG"
        echo "${GREEN}✅ 已强制补全全套 SSH 全局配置（密钥/自动登录/心跳保活）${NC}"
    fi
}

# 读取当前启用插件
get_active_plugin() {
    if [[ -f "$PLUGIN_CONF" ]]; then
        cat "$PLUGIN_CONF"
    else
        echo "none"
    fi
}

# 设置启用插件
set_active_plugin() {
    echo "$1" > "$PLUGIN_CONF"
}

# 检测brew是否可用
check_brew() {
    if ! command -v brew &>/dev/null; then
        echo "${RED}错误：未检测到 Homebrew，请先安装 Homebrew${NC}"
        return 1
    fi
    return 0
}

# 检测插件是否已安装
is_installed() {
    local name="$1"
    command -v "$name" &>/dev/null
}

# ========== 插件管理 s -p (仅 prismtty) ==========
plugin_manager() {
    clear
    echo "${CYAN}===== SSH 彩色增强插件管理 =====${NC}"
    local active=$(get_active_plugin)
    echo "当前启用插件: ${GREEN}$active${NC}"
    echo ""
    echo "请选择操作："
    echo "  1) 安装 & 启用 prismtty (网络/服务器输出高亮)"
    echo "  2) 停用增强插件"
    echo "  3) 卸载 prismtty"
    echo "  q) 退出"
    echo ""
    read "opt?请输入选项: "

    case "$opt" in
        1)
            if ! check_brew; then return 1; fi
            echo "${BLUE}添加 inxbit/tap 源并安装 prismtty...${NC}"
            if ! is_installed "prismtty"; then
                brew tap inxbit/tap
                brew install prismtty
            fi
            set_active_plugin "prismtty"
            echo "${GREEN}✅ 已启用 prismtty，后续连接自动高亮${NC}"
            ;;
        2)
            set_active_plugin "none"
            echo "${YELLOW}✅ 已停用彩色增强插件${NC}"
            ;;
        3)
            if ! check_brew; then return 1; fi
            if is_installed "prismtty"; then
                brew uninstall prismtty
                [[ $(get_active_plugin) == "prismtty" ]] && set_active_plugin "none"
                echo "${GREEN}✅ 已卸载 prismtty${NC}"
            else
                echo "${YELLOW}prismtty 未安装${NC}"
            fi
            ;;
        q|Q)
            echo "${YELLOW}已退出插件管理${NC}"
            ;;
        *)
            echo "${RED}无效选项${NC}"
            ;;
    esac
}

# SSH 命令包装
ssh_wrapper() {
    local host="$1"
    local plugin=$(get_active_plugin)
    case "$plugin" in
        prismtty)
            exec prismtty -- ssh "$host"
            ;;
        none|*)
            exec ssh "$host"
            ;;
    esac
}

# 提取所有主机别名
raw_hosts() {
    /usr/bin/awk '
    /^[[:space:]]*Host[[:space:]]+[^#]/ {
        n = $2
        if (n != "" && n != "*" && n !~ /^[0-9]+$/) print n
    }' "$SSH_CONFIG" 2>/dev/null | sort -u
}

# 获取单台主机信息
get_host_info() {
    local host="$1"
    local in_block=0
    local host_name="" user="" port="22" key="" login_type="key" pass=""

    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*Host[[:space:]]+"$host" ]]; then
            in_block=1
            continue
        fi
        [[ $line =~ ^[[:space:]]*Host[[:space:]]+ ]] && in_block=0
        [[ $in_block -ne 1 ]] && continue

        [[ $line =~ HostName[[:space:]]+(.+) ]] && host_name="${match[1]}"
        [[ $line =~ User[[:space:]]+(.+) ]] && user="${match[1]}"
        [[ $line =~ Port[[:space:]]+(.+) ]] && port="${match[1]}"
        [[ $line =~ IdentityFile[[:space:]]+(.+) ]] && key="${match[1]}"
        [[ $line =~ ^[[:space:]]*#LoginType[[:space:]]+(.+) ]] && login_type="${match[1]}"
        [[ $line =~ ^[[:space:]]*#Pass[[:space:]]+(.+) ]] && pass="${match[1]}"
    done < "$SSH_CONFIG"

    echo "$host_name|$user|$port|$key|$login_type|$pass"
}

# 列出所有服务器
list_all() {
    echo "\n${BLUE}===== 服务器列表 =====${NC}"
    local out=$(raw_hosts)
    if [[ -z $out ]]; then
        echo "${YELLOW}暂无服务器${NC}"
    else
        raw_hosts | while IFS= read -r line; do
            local info=$(get_host_info "$line")
            local ltype=${info#*|*|*|*|}; ltype=${ltype%%|*}
            local tag=""
            [[ $ltype == "password" ]] && tag="${GRAY}(密码登录)${NC}"
            echo "${GREEN}• $line $tag${NC}"
        done
    fi
    echo "${BLUE}======================${NC}\n"
}

# 查看单台主机配置
view_info() {
    local h="$2"
    [[ -z $h ]] && read "h?输入别名: "
    if ! /usr/bin/grep -E "^[[:space:]]*Host[[:space:]]+$h" "$SSH_CONFIG" &>/dev/null; then
        echo "${RED}别名不存在${NC}"
        return 1
    fi
    echo ""
    /usr/bin/awk -v t="$h" '
        flag=0
        /^[[:space:]]*Host[[:space:]]+'"$h"'/ {flag=1}
        flag {print}
        /^[[:space:]]*Host[[:space:]]+/ && flag {exit}
    ' "$SSH_CONFIG"
    echo ""
}

# 新增主机
add_host() {
    read "host_alias?服务器别名: "
    if [[ -z $host_alias || $host_alias =~ ^[0-9]+$ ]]; then
        echo "${RED}别名非法，不能为空/纯数字${NC}"
        return 1
    fi
    if /usr/bin/grep -E "^[[:space:]]*Host[[:space:]]+$host_alias" "$SSH_CONFIG" &>/dev/null; then
        echo "${RED}别名已存在${NC}"
        return 1
    fi

    read "host_ip?目标IP/域名: "
    read "host_user?登录用户名: "
    read "host_port?端口(默认22): "; host_port=${host_port:-22}

    read "login_mode?登录方式(1=私钥 2=密码): "
    local login_type="key"
    local target_key=""
    local host_pass=""

    if [[ $login_mode == "2" ]]; then
        login_type="password"
        read -s "host_pass?登录密码: "
        echo ""
    else
        read "target_key?私钥路径: "
    fi

    read "use_proxy?是否使用跳板机(y/n): "
    local proxy_jump=""
    if [[ $use_proxy == [Yy] ]]; then
        read "proxy_alias?跳板机别名: "
        proxy_jump="  ProxyJump $proxy_alias"
    fi

    {
        echo ""
        echo "Host $host_alias"
        echo "  HostName $host_ip"
        echo "  User $host_user"
        echo "  Port $host_port"
        echo "  #LoginType $login_type"
        if [[ $login_type == "key" && -n $target_key ]]; then
            echo "  IdentityFile $target_key"
        fi
        [[ -n $proxy_jump ]] && echo "$proxy_jump"
        [[ $login_type == "password" && -n $host_pass ]] && echo "  #Pass $host_pass"
    } >> "$SSH_CONFIG"

    chmod 600 "$SSH_CONFIG"
    echo "${GREEN}✅ 服务器配置添加完成${NC}"
}

# 删除指定Host区块
safe_del() {
    local target="$1"
    local tmp=$(mktemp)
    local in_block=0

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ $line =~ ^[[:space:]]*"Host $target"[[:space:]]*$ ]]; then
            in_block=1
            continue
        fi
        if [[ $line =~ ^[[:space:]]*Host[[:space:]]+ && $in_block -eq 1 ]]; then
            in_block=0
        fi
        if [[ $in_block -eq 0 ]]; then
            echo "$line" >> "$tmp"
        fi
    done < "$SSH_CONFIG"

    mv "$tmp" "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
}

# 修改主机配置
edit_host() {
    read "h?要修改的别名: "
    if ! /usr/bin/grep -E "^[[:space:]]*Host[[:space:]]+$h" "$SSH_CONFIG" &>/dev/null; then
        echo "${RED}别名不存在${NC}"
        return 1
    fi

    local old_ip="" old_user="" old_port="22" old_key="" old_pass=""
    local proxy_alias="" use_proxy="n" old_login="key"
    local in_block=0

    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*Host[[:space:]]+"$h" ]]; then
            in_block=1
            continue
        fi
        [[ $line =~ ^[[:space:]]*Host[[:space:]]+ ]] && in_block=0
        [[ $in_block -ne 1 ]] && continue

        [[ $line =~ HostName[[:space:]]+(.+) ]] && old_ip="${match[1]}"
        [[ $line =~ User[[:space:]]+(.+) ]] && old_user="${match[1]}"
        [[ $line =~ Port[[:space:]]+(.+) ]] && old_port="${match[1]}"
        [[ $line =~ IdentityFile[[:space:]]+(.+) ]] && old_key="${match[1]}"
        [[ $line =~ ProxyJump[[:space:]]+(.+) ]] && { proxy_alias="${match[1]}"; use_proxy="y"; }
        [[ $line =~ ^[[:space:]]*#LoginType[[:space:]]+(key|password) ]] && old_login="${match[1]}"
        [[ $line =~ ^[[:space:]]*#Pass[[:space:]]+(.+) ]] && old_pass="${match[1]}"
    done < "$SSH_CONFIG"

    echo "${YELLOW}--- 原有配置，直接回车保留原值 ---${NC}"
    read "new_ip?IP/域名[$old_ip]: "; new_ip=${new_ip:-$old_ip}
    read "new_user?用户名[$old_user]: "; new_user=${new_user:-$old_user}
    read "new_port?端口[$old_port]: "; new_port=${new_port:-$old_port}

    echo "当前登录方式：$old_login"
    read "new_login?修改方式(1=私钥 2=密码 回车不变): "
    local new_login="$old_login"
    local new_key="$old_key"
    local new_pass="$old_pass"

    if [[ $new_login == "1" || $new_login == "2" ]]; then
        if [[ $new_login == "2" ]]; then
            new_login="password"
            read -s "new_pass?新密码: "; echo ""
            new_key=""
        else
            new_login="key"
            read "new_key?新私钥路径[$old_key]: "; new_key=${new_key:-$old_key}
            new_pass=""
        fi
    fi

    read "new_proxy?使用跳板机(y/n)[$use_proxy]: "; new_proxy=${new_proxy:-$use_proxy}
    local proxy_jump=""
    if [[ $new_proxy == [Yy] ]]; then
        read "pa?跳板机别名[$proxy_alias]: "; pa=${pa:-$proxy_alias}
        proxy_jump="  ProxyJump $pa"
    fi

    safe_del "$h"
    {
        echo ""
        echo "Host $h"
        echo "  HostName $new_ip"
        echo "  User $new_user"
        echo "  Port $new_port"
        echo "  #LoginType $new_login"
        if [[ $new_login == "key" && -n $new_key ]]; then
            echo "  IdentityFile $new_key"
        fi
        [[ -n $proxy_jump ]] && echo "$proxy_jump"
        [[ $new_pass != "" ]] && echo "  #Pass $new_pass"
    } >> "$SSH_CONFIG"

    chmod 600 "$SSH_CONFIG"
    echo "${GREEN}✅ 配置修改完成${NC}"
}

# 删除主机
del_host() {
    read "h?要删除的别名: "
    if ! /usr/bin/grep -E "^[[:space:]]*Host[[:space:]]+$h" "$SSH_CONFIG" &>/dev/null; then
        echo "${RED}别名不存在${NC}"
        return 1
    fi
    read "ok?确认删除?(y/n): "
    [[ $ok != [Yy] ]] && echo "${YELLOW}已取消${NC}" && return 0
    safe_del "$h"
    echo "${GREEN}✅ 删除成功${NC}"
}

# 启动ssh-agent
start_ssh_agent() {
    if [[ -z "$SSH_AUTH_SOCK" ]]; then
        eval "$(ssh-agent -s)" >/dev/null 2>&1
    fi
    ssh-add --apple-load-keychain >/dev/null 2>&1
}

# 获取私钥路径
get_key_path() {
    local host="$1"
    local key_path=""
    local in_block=0
    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*Host[[:space:]]+"$host" ]]; then
            in_block=1
            continue
        fi
        [[ $line =~ ^[[:space:]]*Host[[:space:]]+ ]] && in_block=0
        [[ $in_block -ne 1 ]] && continue
        if [[ $line =~ IdentityFile[[:space:]]+(.+) ]]; then
            key_path="${match[1]}"
            break
        fi
    done < "$SSH_CONFIG"
    echo "$key_path"
}

# 私钥托管到钥匙串
add_key_keychain() {
    local tmpfile=$(mktemp)
    raw_hosts > "$tmpfile"
    local total=$(wc -l < "$tmpfile")
    if (( total == 0 )); then
        echo "${YELLOW}暂无服务器${NC}"
        rm -f "$tmpfile"
        return 1
    fi

    local idx=1
    local old_stty=$(stty -g)
    stty -echo -icanon -isig

    while true; do
        clear
        echo "${CYAN}===== 选择服务器托管私钥 =====${NC}"
        local line_num=1
        local target_name=""
        while IFS= read -r name; do
            if (( line_num == idx )); then
                printf "${GREEN} → %s${NC}\n" "$name"
                target_name="$name"
            else
                printf "    %s\n" "$name"
            fi
            ((line_num++))
        done < "$tmpfile"

        local key
        read -r -k 1 key
        case "$key" in
            $'\e')
                read -r -k 1 key
                [[ $key == "[" ]] && read -r -k 1 key
                case "$key" in
                    A) ((idx--)); (( idx < 1 )) && idx=$total ;;
                    B) ((idx++)); (( idx > total )) && idx=1 ;;
                esac
                ;;
            $'\r'|$'\n')
                stty "$old_stty"
                local kpath=$(get_key_path "$target_name")
                if [[ -z $kpath || ! -f $kpath ]]; then
                    echo "${RED}❌ 私钥文件不存在${NC}"
                    rm -f "$tmpfile"
                    return 1
                fi
                ssh-add --apple-use-keychain "$kpath"
                [[ $? -eq 0 ]] && echo "${GREEN}✅ 私钥托管成功${NC}" || echo "${RED}❌ 托管失败${NC}"
                rm -f "$tmpfile"
                return 0
            ;;
            q|Q)
                stty "$old_stty"
                echo "${YELLOW}已退出${NC}"
                rm -f "$tmpfile"
                return 0
        esac
    done
}

# 光标选择服务器连接
cursor_select() {
    start_ssh_agent
    local tmpfile=$(mktemp)
    raw_hosts > "$tmpfile"

    local total=$(wc -l < "$tmpfile")
    if (( total == 0 )); then
        echo "${YELLOW}暂无服务器，请先添加${NC}"
        rm -f "$tmpfile"
        return 1
    fi

    local idx=1
    local old_stty=$(stty -g)
    stty -echo -icanon -isig

    while true; do
        clear
        echo "${CYAN}===== ↑↓ 切换 | 回车连接 | q 退出 =====${NC}"
        local line_num=1
        local target_name=""
        while IFS= read -r name; do
            if (( line_num == idx )); then
                printf "${GREEN} → %s${NC}\n" "$name"
                target_name="$name"
            else
                printf "    %s\n" "$name"
            fi
            ((line_num++))
        done < "$tmpfile"

        local key
        read -r -k 1 key
        case "$key" in
            $'\e')
                read -r -k 1 key
                [[ $key == "[" ]] && read -r -k 1 key
                case "$key" in
                    A) ((idx--)); (( idx < 1 )) && idx=$total ;;
                    B) ((idx++)); (( idx > total )) && idx=1 ;;
                esac
                ;;
            $'\r'|$'\n')
                stty "$old_stty"
                clear
                echo "${BLUE}正在连接 → ${GREEN}$target_name${NC}"
                ssh_wrapper "$target_name"

                echo -e "\n${YELLOW}连接结束，按回车返回...${NC}"
                read
                rm -f "$tmpfile"
                return 0
            ;;
            q|Q)
                stty "$old_stty"
                clear
                echo "${YELLOW}已退出${NC}"
                rm -f "$tmpfile"
                return 0
        esac
    done
}

# 版本&状态查看
show_version() {
    echo "当前工具版本：${GREEN}$VERSION${NC}"
    echo "脚本路径：$SCRIPT_PATH"
    local active=$(get_active_plugin)
    echo "彩色增强插件：${GREEN}$active${NC}"
    echo "SSH 全局配置：已完整启用（密钥/自动登录/心跳保活）"
}

# 自动更新
auto_update() {
    echo "${BLUE}正在检测版本更新...${NC}"
    if ! command -v curl &>/dev/null; then
        echo "${RED}错误：未检测到 curl，无法更新${NC}"
        return 1
    fi

    local tmp_file=$(mktemp)
    curl -fsSL "$UPDATE_URL" -o "$tmp_file"
    if [[ ! -s "$tmp_file" ]]; then
        echo "${RED}错误：下载远端脚本失败${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    local remote_ver
    remote_ver=$(grep '^VERSION="' "$tmp_file" | head -n1 | cut -d'"' -f2)

    if [[ "$remote_ver" == "$VERSION" ]]; then
        echo "${GREEN}✅ 当前已是最新版本${NC}"
    else
        echo "${YELLOW}发现新版本，开始更新...${NC}"
        sudo cp -f "$tmp_file" "$SCRIPT_PATH"
        echo "${GREEN}✅ 更新完成，请重新执行 s${NC}"
    fi
    rm -f "$tmp_file"
}

# 帮助
show_help() {
    echo "${CYAN}=== SSH 快捷连接工具 $VERSION ===${NC}"
    echo "${GREEN}s          ${NC}光标选择服务器连接"
    echo "${GREEN}s -a       ${NC}新增服务器"
    echo "${GREEN}s -e       ${NC}修改服务器"
    echo "${GREEN}s -d       ${NC}删除服务器"
    echo "${GREEN}s -l       ${NC}列出所有服务器"
    echo "${GREEN}s -v       ${NC}查看指定服务器配置"
    echo "${GREEN}s -k       ${NC}私钥托管到钥匙串"
    echo "${GREEN}s -p       ${NC}prismtty 插件管理"
    echo "${GREEN}s -ver     ${NC}查看版本与状态"
    echo "${GREEN}s -update  ${NC}一键更新脚本"
    echo "${GREEN}s -h       ${NC}查看帮助"
    echo "${CYAN}--------------------------------------------------${NC}"
    echo "特性：首次运行/配置缺失 自动强制补全全套 Host * 全局配置 + 心跳保活"
}

# 入口
init_env
case "$1" in
    -a) add_host ;;
    -e) edit_host ;;
    -d) del_host ;;
    -l) list_all ;;
    -v) view_info "$@" ;;
    -k) add_key_keychain ;;
    -p) plugin_manager ;;
    -ver) show_version ;;
    -update) auto_update ;;
    -h) show_help ;;
    "") cursor_select ;;
    *) echo "${RED}未知参数，使用 s -h 查看帮助${NC}" ;;
esac
EOF

sudo mv ~/ssh_tool_color /usr/local/bin/s
sudo chmod +x /usr/local/bin/s

echo -e "\n${GREEN}✅ 最终版脚本部署完成！${NC}"
echo -e "功能：缺任意一条全局配置 → 自动重建完整 Host * 区块"
