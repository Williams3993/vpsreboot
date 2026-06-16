#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 每天重启的小时(24小时制),如需改成其他时间只改这一个值即可
REBOOT_HOUR=14

echo "=================================="
echo "定时重启设置脚本（保留VPS当地时区）"
echo "=================================="

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
    echo "请使用: sudo bash $0"
    exit 1
fi

# ---------- 工具函数 ----------
# 探测公网IPv4(多端点容错)
get_ipv4() {
    local ip
    for url in "https://api.ipify.org" "https://ipv4.icanhazip.com" "https://api-ipv4.ip.sb/ip" "https://ifconfig.me/ip"; do
        ip=$(curl -s4 --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
        if echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
            echo "$ip"; return 0
        fi
    done
    echo ""
}

# 探测公网IPv6(多端点容错)
get_ipv6() {
    local ip
    for url in "https://api6.ipify.org" "https://ipv6.icanhazip.com" "https://api-ipv6.ip.sb/ip"; do
        ip=$(curl -s6 --max-time 5 "$url" 2>/dev/null | tr -d '[:space:]')
        if echo "$ip" | grep -qE ':.*:'; then
            echo "$ip"; return 0
        fi
    done
    echo ""
}

# 查询IP归属地(国家 省/区 城市),返回中文
geo_lookup() {
    local target="$1" json
    [ -z "$target" ] && { echo ""; return; }
    for base in "http://ip-api.com/json" "https://ip-api.com/json"; do
        json=$(curl -s --max-time 6 "${base}/${target}?lang=zh-CN&fields=status,country,regionName,city" 2>/dev/null)
        if echo "$json" | grep -q '"status":"success"'; then
            local country region city
            country=$(echo "$json" | sed -n 's/.*"country":"\([^"]*\)".*/\1/p')
            region=$(echo "$json" | sed -n 's/.*"regionName":"\([^"]*\)".*/\1/p')
            city=$(echo "$json" | sed -n 's/.*"city":"\([^"]*\)".*/\1/p')
            echo "$(echo "$country $region $city" | sed 's/  */ /g; s/^ *//; s/ *$//')"
            return 0
        fi
    done
    echo ""
}

echo -e "${YELLOW}[1/5] 检测系统类型...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}系统: $PRETTY_NAME${NC}"
else
    echo -e "${YELLOW}无法检测系统类型,继续执行...${NC}"
fi

# 不修改时区，仅读取VPS当前所在时区
echo -e "\n${YELLOW}[2/5] 读取VPS当前时区(不做修改)...${NC}"
if command -v timedatectl &> /dev/null; then
    CURRENT_TZ=$(timedatectl show -p Timezone --value 2>/dev/null)
fi
[ -z "$CURRENT_TZ" ] && CURRENT_TZ=$(cat /etc/timezone 2>/dev/null)
[ -z "$CURRENT_TZ" ] && CURRENT_TZ=$(readlink -f /etc/localtime 2>/dev/null | sed 's#.*/zoneinfo/##')
[ -z "$CURRENT_TZ" ] && CURRENT_TZ="未知"
echo -e "${GREEN}✓ 已读取当前时区: ${CURRENT_TZ}${NC}"

# 探测公网IP与归属地
echo -e "\n${YELLOW}[3/5] 探测公网IP与归属地(需要联网,稍候)...${NC}"
IPV4=$(get_ipv4)
IPV6=$(get_ipv6)
GEO=$(geo_lookup "${IPV4:-$IPV6}")
[ -z "$IPV4" ] && IPV4="无 / 未检测到"
[ -z "$IPV6" ] && IPV6="无 / 未检测到"
[ -z "$GEO" ]  && GEO="查询失败(可能无外网或API限流)"
echo -e "${GREEN}✓ IPv4: ${IPV4}${NC}"
echo -e "${GREEN}✓ IPv6: ${IPV6}${NC}"
echo -e "${GREEN}✓ 归属: ${GEO}${NC}"

# 配置定时重启（每天当地时间 REBOOT_HOUR 点）
echo -e "\n${YELLOW}[4/5] 配置每天 ${REBOOT_HOUR}:00 (VPS当地时间) 定时重启...${NC}"
crontab -l > /tmp/current_cron 2>/dev/null || touch /tmp/current_cron
if grep -q "reboot" /tmp/current_cron; then
    echo -e "${YELLOW}检测到已存在的重启任务,将进行替换...${NC}"
    sed -i '/reboot/d' /tmp/current_cron
fi
echo "0 ${REBOOT_HOUR} * * * /sbin/reboot" >> /tmp/current_cron
crontab /tmp/current_cron

# 验证crontab是否设置成功
echo -e "\n${YELLOW}[5/5] 验证定时任务设置...${NC}"
if crontab -l | grep -q "0 ${REBOOT_HOUR} \* \* \* /sbin/reboot"; then
    echo -e "${GREEN}✓ 定时重启任务设置成功!${NC}"
else
    echo -e "${RED}✗ 定时重启任务设置失败!${NC}"
    rm -f /tmp/current_cron
    exit 1
fi

# 确保cron服务正在运行
echo -e "\n${YELLOW}检查cron服务状态...${NC}"
if command -v systemctl &> /dev/null; then
    systemctl enable cron 2>/dev/null || systemctl enable crond 2>/dev/null
    systemctl restart cron 2>/dev/null || systemctl restart crond 2>/dev/null
    if systemctl is-active --quiet cron || systemctl is-active --quiet crond; then
        echo -e "${GREEN}✓ Cron服务运行正常${NC}"
    else
        echo -e "${YELLOW}! Cron服务可能未运行,请手动检查${NC}"
    fi
else
    service cron restart 2>/dev/null || service crond restart 2>/dev/null
    echo -e "${GREEN}✓ Cron服务已重启${NC}"
fi
rm -f /tmp/current_cron

# 计算下一次重启的具体时刻(按当地时间)
NOW_HM=$(date '+%H%M')
TARGET_HM=$(printf '%02d00' "$REBOOT_HOUR")
if [ "$NOW_HM" -lt "$TARGET_HM" ]; then
    NEXT_REBOOT="$(date '+%Y-%m-%d') $(printf '%02d:00:00' "$REBOOT_HOUR") (今天)"
else
    NEXT_REBOOT="$(date -d 'tomorrow' '+%Y-%m-%d') $(printf '%02d:00:00' "$REBOOT_HOUR") (明天)"
fi

# ========= 醒目信息块(argosbx风格) =========
echo ""
echo -e "${CYAN}=========== 当前服务器与定时重启配置情况 ===========${NC}"
echo -e "本地IPv4地址 ：${GREEN}${IPV4}${NC}"
echo -e "本地IPv6地址 ：${GREEN}${IPV6}${NC}"
echo -e "IP所属地区   ：${GREEN}${GEO}${NC}"
echo -e "使用时区     ：${GREEN}${CURRENT_TZ}${NC}  ($(date '+%Z %z'))"
echo -e "当前系统时间 ：${GREEN}$(date '+%Y-%m-%d %H:%M:%S')${NC}"
echo -e "每日重启时间 ：${GREEN}$(printf '%02d:00' "$REBOOT_HOUR") (按上面的当地时区)${NC}"
echo -e "下次重启时刻 ：${GREEN}${NEXT_REBOOT}${NC}"
echo -e "${CYAN}====================================================${NC}"
echo ""

# 显示当前所有定时任务
echo -e "${YELLOW}当前所有定时任务:${NC}"
echo "-----------------------------------"
crontab -l
echo "-----------------------------------"

echo -e "\n${GREEN}配置完成!${NC}"
echo -e "${YELLOW}如需取消定时重启,请运行: crontab -e 并删除含 reboot 的行${NC}"
echo -e "${YELLOW}如需更改重启时间,修改脚本顶部 REBOOT_HOUR 的值后重新运行即可${NC}"

exit 0
