stty sane
sudo rm -f /usr/local/bin/s

cat > ~/ssh_tool_color <<'EOF'
#!/bin/zsh
# SSH 快捷连接 | 零依赖 | 私钥/密码双模式 | 注释存密码(兼容原生SSH)
VERSION="v2.1"
SCRIPT_PATH="/usr/local/bin/s"
UPDATE_URL="https://raw.githubusercontent.com/lg10/mac-ssh/refs/heads/main/mac-ssh.sh"

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

# 初始化目录与权限
init_env() {
    mkdir -p "$SSH_DIR" "$KEYS_DIR"
    chmod 700 "$SSH_DIR" "$KEYS_DIR"
    [[ ! -f "$SSH_CONFIG" ]] && touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
}

# 提取所有合法Host别名
raw_hosts() {
    /usr/bin/awk '
    /^[[:space:]]*Host[[:space:]]+[^#]/ {
        n = $2
        if (n != "" && n != "*" && n !~ /^[0-9]+$/) print n
    }' "$SSH_CONFIG" 2>/dev/null | sort -u
}

# 获取主机信息：#LoginType #Pass 注释字段
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

# 查看单个主机配置详情
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

    # 写入：自定义字段用 # 注释，SSH 不会报错
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

# 安全删除单个Host块
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
        [[ $new_login == "password" && -n $new_pass ]] && echo "  #Pass $new_pass"
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

# 光标选择菜单 + 连接
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
                ssh "$target_name"

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

# 版本查看
show_version() {
    echo "当前工具版本：${GREEN}$VERSION${NC}"
    echo "脚本路径：$SCRIPT_PATH"
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

# 帮助文档
show_help() {
    echo "${CYAN}=== SSH 快捷连接工具 $VERSION（零依赖 · 注释存密码） ===${NC}"
    echo "${GREEN}s          ${NC}光标选择服务器并连接"
    echo "${GREEN}s -a       ${NC}新增服务器（私钥/密码双模式）"
    echo "${GREEN}s -e       ${NC}修改服务器配置"
    echo "${GREEN}s -d       ${NC}删除服务器"
    echo "${GREEN}s -l       ${NC}列出所有服务器"
    echo "${GREEN}s -v       ${NC}查看服务器完整配置"
    echo "${GREEN}s -k       ${NC}托管私钥到系统钥匙串"
    echo "${GREEN}s -ver     ${NC}查看版本"
    echo "${GREEN}s -update  ${NC}一键更新"
    echo "${GREEN}s -h       ${NC}查看本帮助"
    echo "${CYAN}--------------------------------------------------${NC}"
    echo "说明：登录类型/密码存放于 # 注释中，SSH 原生解析无报错"
}

# 入口分发
init_env
case "$1" in
    -a) add_host ;;
    -e) edit_host ;;
    -d) del_host ;;
    -l) list_all ;;
    -v) view_info "$@" ;;
    -k) add_key_keychain ;;
    -ver) show_version ;;
    -update) auto_update ;;
    -h) show_help ;;
    "") cursor_select ;;
    *) echo "${RED}未知参数，使用 s -h 查看帮助${NC}" ;;
esac
EOF

sudo mv ~/ssh_tool_color /usr/local/bin/s
sudo chmod +x /usr/local/bin/s

echo -e "\n${GREEN}✅ 修复完成！SSH 不再报配置项错误${NC}"
echo -e "${YELLOW}原理：登录类型、密码存于 # 注释，仅脚本读取，SSH 忽略注释${NC}"
