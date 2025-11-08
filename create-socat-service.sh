#!/bin/bash

# Socat 端口转发服务创建脚本
# 用法: ./create-socat-service.sh <listen_port> <target_host> [target_port]
# 示例: ./create-socat-service.sh 57074 example.com 57074
# 示例: ./create-socat-service.sh 57074 192.168.1.1 57074

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -lt 2 ]; then
    echo -e "${RED}错误: 参数不足${NC}"
    echo "用法: $0 <listen_port> <target_host> [target_port]"
    echo "示例: $0 57074 example.com 57074"
    echo "示例: $0 57074 192.168.1.1 57074"
    echo ""
    echo "参数说明:"
    echo "  listen_port  - 本地监听端口"
    echo "  target_host  - 目标主机地址（域名或IP）"
    echo "  target_port  - 目标端口（可选，默认与listen_port相同）"
    exit 1
fi

LISTEN_PORT=$1
TARGET_HOST=$2
TARGET_PORT=${3:-$LISTEN_PORT}

# 验证端口是否为数字
if ! [[ "$LISTEN_PORT" =~ ^[0-9]+$ ]] || [ "$LISTEN_PORT" -lt 1 ] || [ "$LISTEN_PORT" -gt 65535 ]; then
    echo -e "${RED}错误: 监听端口必须是1-65535之间的数字${NC}"
    exit 1
fi

if ! [[ "$TARGET_PORT" =~ ^[0-9]+$ ]] || [ "$TARGET_PORT" -lt 1 ] || [ "$TARGET_PORT" -gt 65535 ]; then
    echo -e "${RED}错误: 目标端口必须是1-65535之间的数字${NC}"
    exit 1
fi

# 检查是否为root用户
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}错误: 请使用sudo运行此脚本${NC}"
    exit 1
fi

# 检查socat是否安装
if ! command -v socat &> /dev/null; then
    echo -e "${YELLOW}警告: 未检测到socat，请先安装:${NC}"
    echo "  Ubuntu/Debian: sudo apt-get install -y socat"
    echo "  CentOS/RHEL:   sudo yum install -y socat"
    echo "  Arch Linux:    sudo pacman -S socat"
    exit 1
fi

# 服务名称
SERVICE_TCP="socat-tcp-${LISTEN_PORT}"
SERVICE_UDP="socat-udp-${LISTEN_PORT}"

echo -e "${GREEN}开始创建socat端口转发服务...${NC}"
echo "监听端口: ${LISTEN_PORT}"
echo "目标地址: ${TARGET_HOST}:${TARGET_PORT}"
echo ""

# 创建TCP服务文件
echo -e "${YELLOW}创建TCP服务文件...${NC}"
cat > /etc/systemd/system/${SERVICE_TCP}.service <<EOF
[Unit]
Description=Socat TCP Port Forwarding ${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat TCP-LISTEN:${LISTEN_PORT},reuseaddr,fork TCP:${TARGET_HOST}:${TARGET_PORT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 创建UDP服务文件
echo -e "${YELLOW}创建UDP服务文件...${NC}"
cat > /etc/systemd/system/${SERVICE_UDP}.service <<EOF
[Unit]
Description=Socat UDP Port Forwarding ${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}
After=network.target

[Service]
Type=simple
ExecStart=/usr/bin/socat UDP-LISTEN:${LISTEN_PORT},reuseaddr,fork UDP:${TARGET_HOST}:${TARGET_PORT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# 重新加载systemd配置
echo -e "${YELLOW}重新加载systemd配置...${NC}"
systemctl daemon-reload

# 启用并启动TCP服务
echo -e "${YELLOW}启用并启动TCP服务...${NC}"
systemctl enable ${SERVICE_TCP}
systemctl start ${SERVICE_TCP}

# 启用并启动UDP服务
echo -e "${YELLOW}启用并启动UDP服务...${NC}"
systemctl enable ${SERVICE_UDP}
systemctl start ${SERVICE_UDP}

# 等待服务启动
sleep 2

# 检查服务状态
echo ""
echo -e "${GREEN}服务创建完成！${NC}"
echo ""
echo "服务状态:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
systemctl status ${SERVICE_TCP} --no-pager -l | head -n 5
echo ""
systemctl status ${SERVICE_UDP} --no-pager -l | head -n 5
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "常用命令:"
echo "  查看TCP服务状态: sudo systemctl status ${SERVICE_TCP}"
echo "  查看UDP服务状态: sudo systemctl status ${SERVICE_UDP}"
echo "  停止TCP服务:     sudo systemctl stop ${SERVICE_TCP}"
echo "  停止UDP服务:     sudo systemctl stop ${SERVICE_UDP}"
echo "  重启TCP服务:     sudo systemctl restart ${SERVICE_TCP}"
echo "  重启UDP服务:     sudo systemctl restart ${SERVICE_UDP}"
echo "  禁用TCP服务:     sudo systemctl disable ${SERVICE_TCP}"
echo "  禁用UDP服务:     sudo systemctl disable ${SERVICE_UDP}"
echo "  查看日志:        sudo journalctl -u ${SERVICE_TCP} -f"
echo "  查看日志:        sudo journalctl -u ${SERVICE_UDP} -f"

