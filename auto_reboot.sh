#!/bin/bash

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo "=================================="
echo "系统时区配置与定时重启设置脚本"
echo "=================================="

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then 
    echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
    echo "请使用: sudo bash $0"
    exit 1
fi

echo -e "${YELLOW}[1/4] 检测系统类型...${NC}"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    echo -e "${GREEN}系统: $PRETTY_NAME${NC}"
else
    echo -e "${YELLOW}无法检测系统类型,继续执行...${NC}"
fi

# 设置时区为北京时间
echo -e "\n${YELLOW}[2/4] 设置系统时区为北京时间(Asia/Shanghai)...${NC}"
ln -sf /usr/share/zoneinfo/Asia/Shanghai /etc/localtime

# 更新系统时区配置
if command -v timedatectl &> /dev/null; then
    timedatectl set-timezone Asia/Shanghai
    echo -e "${GREEN}✓ 时区已设置为 Asia/Shanghai${NC}"
    echo -e "当前系统时间: $(date '+%Y-%m-%d %H:%M:%S %Z')"
else
    echo "Asia/Shanghai" > /etc/timezone
    echo -e "${GREEN}✓ 时区已设置为 Asia/Shanghai${NC}"
    echo -e "当前系统时间: $(date '+%Y-%m-%d %H:%M:%S')"
fi

# 同步系统时间(如果有网络连接)
if command -v ntpdate &> /dev/null; then
    echo -e "${YELLOW}正在同步网络时间...${NC}"
    ntpdate -u pool.ntp.org 2>/dev/null && echo -e "${GREEN}✓ 时间同步成功${NC}" || echo -e "${YELLOW}时间同步失败(可能无网络连接)${NC}"
fi

# 配置定时重启
echo -e "\n${YELLOW}[3/4] 配置每天凌晨4点定时重启...${NC}"

# 备份现有的crontab
crontab -l > /tmp/current_cron 2>/dev/null || touch /tmp/current_cron

# 检查是否已存在重启任务
if grep -q "reboot" /tmp/current_cron; then
    echo -e "${YELLOW}检测到已存在的重启任务,将进行替换...${NC}"
    # 删除所有包含reboot的行
    sed -i '/reboot/d' /tmp/current_cron
fi

# 添加新的定时重启任务
echo "0 4 * * * /sbin/reboot" >> /tmp/current_cron

# 安装新的crontab
crontab /tmp/current_cron

# 验证crontab是否设置成功
echo -e "\n${YELLOW}[4/4] 验证定时任务设置...${NC}"
if crontab -l | grep -q "0 4 \* \* \* /sbin/reboot"; then
    echo -e "${GREEN}✓ 定时重启任务设置成功!${NC}"
    echo -e "${GREEN}✓ 系统将在每天凌晨 4:00 自动重启${NC}"
else
    echo -e "${RED}✗ 定时重启任务设置失败!${NC}"
    rm /tmp/current_cron
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

# 显示当前所有定时任务
echo -e "\n${YELLOW}当前所有定时任务:${NC}"
echo "-----------------------------------"
crontab -l
echo "-----------------------------------"

# 清理临时文件
rm /tmp/current_cron

echo -e "\n${GREEN}=================================="
echo "配置完成!"
echo "==================================${NC}"
echo -e "✓ 时区: Asia/Shanghai (北京时间)"
echo -e "✓ 当前时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo -e "✓ 定时重启: 每天凌晨 4:00"
echo -e "\n${YELLOW}提示: 系统将在每天凌晨4点自动重启${NC}"
echo -e "${YELLOW}如需取消定时重启,请运行: crontab -e 并删除相关行${NC}"

exit 0
