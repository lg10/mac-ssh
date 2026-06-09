stty sane
sudo rm -f /usr/local/bin/s

cat > ~/ssh_tool_color <<'EOF'
#!/bin/zsh
# SSH 快捷连接工具 + 彩色菜单/提示
VERSION="v1.6-color"
SCRIPT_PATH="/usr/local/bin/s"
UPDATE_URL="https://raw.githubusercontent.com/lg10/mac-ssh/refs/heads/main/mac-ssh.sh"

# ---------- 颜色定义 ----------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
GRAY='\033[0;37m'
NC='\033[0m' # No Color

SSH_CONFIG="$HOME/.ssh/config"
SSH_DIR="$HOME/.ssh"
KEYS_DIR="$SSH_DIR/keys"
setopt NO_GLOB_SUBST

trap 'stty sane; exit' EXIT INT QUIT TERM

init_env() {
    mkdir -p "$SSH_DIR" "$KEYS_DIR"
    chmod 700 "$SSH_DIR" "$KEYS_DIR"
    [[ ! -f "$SSH_CONFIG" ]] && touch "$SSH_CONFIG"
    chmod 600 "$SSH_CONFIG"
}

raw_hosts() {
    /usr/bin/awk '
    /^[[:space:]]*Host[[:space:]]+[^#]/ {
        n = $2
        if (n != "" && n != "*" && n !~ /^[0-9]+$/) print n
    }' "$SSH_CONFIG" 2>/dev/null | sort -u
}

copy_key() {
    local src="$1"
    local abs=$(eval "echo $src")
    local fname=$(basename "$abs")
    local dst="$KEYS_DIR/$fname"
    cp -f "$abs" "$dst"
    chmod 600 "$dst"
    echo "$dst"
}

list_all() {
    echo "\n${BLUE}===== 服务器列表 =====${NC}"
    local out=$(raw_hosts)
    if [[ -z $out ]]; then
        echo "${YELLOW}暂无服务器${NC}"
    else
        raw_hosts | while IFS= read -r line; do
            echo "${GREEN}• $line${NC}"
        done
    fi
    echo "${BLUE}======================${NC}\n"
}

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

add_host() {
    read "host_alias?服务器别名: "
    if [[ -z $host_alias ]]; then
        echo "${RED}别名不能为空${NC}"
        return 1
    fi
    if [[ $host_alias =~ ^[0-9]+$ ]]; then
        echo "${RED}别名不能为纯数字${NC}"
        return 1
    fi
    if /usr/bin/grep -E "^[[:space:]]*Host[[:space:]]+$host_alias" "$SSH_CONFIG" &>/dev/null; then
        echo "${RED}别名已存在${NC}"
        return 1
    fi

    read "host_ip?目标服务器IP/域名: "
    read "host_user?登录用户名: "
    read "host_port?端口(默认22): "; host_port=${host_port:-22}
    read "target_key?目标机私钥路径(跳板机内路径): "
    read "use_proxy?是否使用跳板机(y/n): "

    local proxy_jump=""
    if [[ $use_proxy == [Yy] ]]; then
        read "proxy_alias?跳板机别名(已存在于配置中): "
        proxy_jump="  ProxyJump $proxy_alias"
    fi

    {
        echo ""
        echo "Host $host_alias"
        echo "  HostName $host_ip"
        echo "  User $host_user"
        echo "  Port $host_port"
        echo "  IdentityFile $target_key"
        [[ -n $proxy_jump ]] && echo "$proxy_jump"
    } >> "$SSH_CONFIG"

    chmod 600 "$SSH_CONFIG"
    echo "${GREEN}✅ 服务器配置添加完成${NC}"
}

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

edit_host() {
    read "h?要修改的别名: "
    if ! /usr/bin/grep -E "^[[:space:]]*Host[[:space:]]+$h" "$SSH_CONFIG" &>/dev/null; then
        echo "${RED}别名不存在${NC}"
        return 1
    fi

    local old_ip="" old_user="" old_port="22" old_key="" proxy_alias=""
    local use_proxy="n"
    local in_block=0

    while IFS= read -r line; do
        if [[ $line =~ ^[[:space:]]*Host[[:space:]]+"$h" ]]; then
            in_block=1
            continue
        fi
        [[ $line =~ ^[[:space:]]*Host[[:space:]]+ ]] && in_block=0
        [[ $in_block -ne 1 ]] && continue

        if [[ $line =~ HostName[[:space:]]+(.+) ]]; then
            old_ip="${match[1]}"
        elif [[ $line =~ User[[:space:]]+(.+) ]]; then
            old_user="${match[1]}"
        elif [[ $line =~ Port[[:space:]]+(.+) ]]; then
            old_port="${match[1]}"
        elif [[ $line =~ IdentityFile[[:space:]]+(.+) ]]; then
            old_key="${match[1]}"
        elif [[ $line =~ ProxyJump[[:space:]]+(.+) ]]; then
            proxy_alias="${match[1]}"
            use_proxy="y"
        fi
    done < "$SSH_CONFIG"

    echo "${YELLOW}--- 原有配置，直接回车保留原值 ---${NC}"
    read "new_ip?IP/域名[$old_ip]: "; new_ip=${new_ip:-$old_ip}
    read "new_user?用户名[$old_user]: "; new_user=${new_user:-$old_user}
    read "new_port?端口[$old_port]: "; new_port=${new_port:-$old_port}
    read "new_key?私钥路径[$old_key]: "; new_key=${new_key:-$old_key}
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
        echo "  IdentityFile $new_key"
        [[ -n $proxy_jump ]] && echo "$proxy_jump"
    } >> "$SSH_CONFIG"

    chmod 600 "$SSH_CONFIG"
    echo "${GREEN}✅ 配置修改完成${NC}"
}

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

start_ssh_agent() {
    if [[ -z "$SSH_AUTH_SOCK" ]]; then
        eval "$(ssh-agent -s)" >/dev/null 2>&1
    fi
    ssh-add --apple-load-keychain >/dev/null 2>&1
}

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
        echo "${CYAN}===== 选择服务器托管私钥（↑↓切换 | 回车确认 | q 退出） =====${NC}"
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
                echo "服务器：${GREEN}$target_name${NC}"
                echo "私钥路径：${CYAN}$kpath${NC}"
                echo "请输入私钥密码（仅一次，永久保存到钥匙串）："
                chmod 600 "$kpath"
                ssh-add --apple-use-keychain "$kpath"
                [[ $? -eq 0 ]] && echo "${GREEN}✅ 托管成功，永久免密${NC}" || echo "${RED}❌ 托管失败${NC}"
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

show_version() {
    echo "当前工具版本：${GREEN}$VERSION${NC}"
    echo "脚本路径：$SCRIPT_PATH"
}

auto_update() {
    echo "${BLUE}正在检测版本更新...${NC}"
    if ! command -v curl &>/dev/null; then
        echo "${RED}错误：未检测到 curl，无法更新${NC}"
        return 1
    fi

    local tmp_file=$(mktemp)
    # 下载远端脚本
    curl -fsSL "$UPDATE_URL" -o "$tmp_file"
    if [[ ! -s "$tmp_file" ]]; then
        echo "${RED}错误：下载远端脚本失败，请检查网络${NC}"
        rm -f "$tmp_file"
        return 1
    fi

    # 提取远端 VERSION 变量值
    local remote_ver
    remote_ver=$(grep '^VERSION="' "$tmp_file" | head -n1 | cut -d'"' -f2)

    if [[ "$remote_ver" == "$VERSION" ]]; then
        echo "${GREEN}✅ 当前已是最新版本($VERSION)，无需更新${NC}"
        rm -f "$tmp_file"
        return 0
    fi

    # 版本不一致，执行更新
    echo "${YELLOW}发现新版本：$remote_ver，开始更新...${NC}"
    sudo cp -f "$tmp_file" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"
    rm -f "$tmp_file"
    echo "${GREEN}✅ 更新完成，请重新执行 s${NC}"
}

show_help() {
    echo "${CYAN}=== SSH 快捷连接工具 $VERSION ===${NC}"
    echo "${GREEN}s          ${NC}光标选择服务器并连接（上下箭头）"
    echo "${GREEN}s -a       ${NC}新增服务器（支持跳板+跳板私钥）"
    echo "${GREEN}s -e       ${NC}修改服务器配置【直接回车保留原值】"
    echo "${GREEN}s -d       ${NC}删除服务器"
    echo "${GREEN}s -l       ${NC}列出所有服务器"
    echo "${GREEN}s -v       ${NC}查看服务器配置详情"
    echo "${GREEN}s -k       ${NC}托管私钥密码到钥匙串（永久免密）"
    echo "${GREEN}s -ver     ${NC}查看当前版本"
    echo "${GREEN}s -update  ${NC}一键自动更新"
    echo "${GREEN}s -h       ${NC}查看本帮助"
    echo "${CYAN}----------------------------------------${NC}"
    echo "使用说明："
    echo "1. 跳板机需提前添加到配置中"
    echo "2. 目标机私钥路径填写【跳板机内的绝对路径】"
    echo "3. 跳板机本地必须存放对应私钥并修复权限"
    echo "4. 修改配置时，直接回车 = 保留原有值"
    echo "5. 使用 s -k 可一键配置永久免密"
}

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
