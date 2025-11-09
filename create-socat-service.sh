#!/bin/bash

# Socat 端口转发服务创建脚本（支持批量端口）
# 用法: ./create-socat-service.sh <target_host> <port1> [port2] [port3] ...
# 示例: ./create-socat-service.sh example.com 57074
# 示例: ./create-socat-service.sh example.com 57074 12693 27057
# 说明: 每个端口都会转发到 target_host:port（监听端口和目标端口相同）

set -e

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 检查参数
if [ $# -lt 2 ]; then
    echo -e "${RED}错误: 参数不足${NC}"
    echo "用法: $0 <target_host> <port1> [port2] [port3] ..."
    echo "示例: $0 example.com 57074"
    echo "示例: $0 example.com 57074 12693 27057"
    echo ""
    echo "参数说明:"
    echo "  target_host  - 目标主机地址（域名或IP）"
    echo "  port1, port2, ... - 要创建的监听端口列表（可多个）"
    echo ""
    echo "说明: 每个端口都会转发到 target_host:port（监听端口和目标端口相同）"
    exit 1
fi

TARGET_HOST=$1
shift  # 移除第一个参数，剩下的都是端口

# 收集所有端口
PORTS=()
for port in "$@"; do
    # 验证端口是否为数字
    if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
        echo -e "${RED}错误: 端口 '$port' 必须是1-65535之间的数字${NC}"
        exit 1
    fi
    PORTS+=("$port")
done

if [ ${#PORTS[@]} -eq 0 ]; then
    echo -e "${RED}错误: 至少需要指定一个端口${NC}"
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

echo -e "${GREEN}开始创建socat端口转发服务...${NC}"
echo -e "${BLUE}目标地址: ${TARGET_HOST}${NC}"
echo -e "${BLUE}端口列表: ${PORTS[*]}${NC}"
echo -e "${BLUE}共 ${#PORTS[@]} 个端口${NC}"
echo ""

# 存储所有创建的服务名称
SERVICES_TCP=()
SERVICES_UDP=()

# 为每个端口创建服务
for LISTEN_PORT in "${PORTS[@]}"; do
    TARGET_PORT=$LISTEN_PORT  # 目标端口与监听端口相同
    SERVICE_TCP="socat-tcp-${LISTEN_PORT}"
    SERVICE_UDP="socat-udp-${LISTEN_PORT}"
    
    SERVICES_TCP+=("${SERVICE_TCP}")
    SERVICES_UDP+=("${SERVICE_UDP}")
    
    echo -e "${YELLOW}[端口 ${LISTEN_PORT}] 创建服务文件...${NC}"
    
    # 创建TCP服务文件
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
done

# 重新加载systemd配置
echo ""
echo -e "${YELLOW}重新加载systemd配置...${NC}"
systemctl daemon-reload

# 启用并启动所有服务
echo -e "${YELLOW}启用并启动所有服务...${NC}"
for SERVICE_TCP in "${SERVICES_TCP[@]}"; do
    systemctl enable ${SERVICE_TCP} > /dev/null 2>&1
    systemctl start ${SERVICE_TCP}
done

for SERVICE_UDP in "${SERVICES_UDP[@]}"; do
    systemctl enable ${SERVICE_UDP} > /dev/null 2>&1
    systemctl start ${SERVICE_UDP}
done

# 等待服务启动
sleep 2

# 检查服务状态
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}所有服务创建完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示每个服务的简要状态
for LISTEN_PORT in "${PORTS[@]}"; do
    SERVICE_TCP="socat-tcp-${LISTEN_PORT}"
    SERVICE_UDP="socat-udp-${LISTEN_PORT}"
    
    echo -e "${BLUE}端口 ${LISTEN_PORT}:${NC}"
    if systemctl is-active --quiet ${SERVICE_TCP} && systemctl is-active --quiet ${SERVICE_UDP}; then
        echo -e "  ${GREEN}✓${NC} TCP服务: ${SERVICE_TCP} (运行中)"
        echo -e "  ${GREEN}✓${NC} UDP服务: ${SERVICE_UDP} (运行中)"
    else
        echo -e "  ${RED}✗${NC} TCP服务: ${SERVICE_TCP} (状态异常)"
        echo -e "  ${RED}✗${NC} UDP服务: ${SERVICE_UDP} (状态异常)"
        echo "  查看详细状态: sudo systemctl status ${SERVICE_TCP}"
        echo "  查看详细状态: sudo systemctl status ${SERVICE_UDP}"
    fi
    echo ""
done

echo "常用命令:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
for LISTEN_PORT in "${PORTS[@]}"; do
    SERVICE_TCP="socat-tcp-${LISTEN_PORT}"
    SERVICE_UDP="socat-udp-${LISTEN_PORT}"
    echo "端口 ${LISTEN_PORT}:"
    echo "  查看状态: sudo systemctl status ${SERVICE_TCP}"
    echo "  查看状态: sudo systemctl status ${SERVICE_UDP}"
    echo "  查看日志: sudo journalctl -u ${SERVICE_TCP} -f"
    echo "  查看日志: sudo journalctl -u ${SERVICE_UDP} -f"
    echo ""
done

# 配置系统内核参数
echo -e "${YELLOW}配置系统内核参数...${NC}"
sudo cp /etc/sysctl.conf /etc/sysctl.conf.bk_$(date +%Y%m%d_%H%M%S) && sudo sh -c 'echo "kernel.pid_max = 65535

kernel.panic = 1

kernel.sysrq = 1

kernel.core_pattern = core_%e

kernel.printk = 3 4 1 3

kernel.numa_balancing = 0

kernel.sched_autogroup_enabled = 0



vm.swappiness = 10

vm.dirty_ratio = 10

vm.dirty_background_ratio = 5

vm.panic_on_oom = 1

vm.overcommit_memory = 1

vm.min_free_kbytes = 39014



net.core.default_qdisc = cake

net.core.netdev_max_backlog = 2000

net.core.rmem_max = 8388608

net.core.wmem_max = 8388608

net.core.rmem_default = 87380

net.core.wmem_default = 65536

net.core.somaxconn = 256

net.core.optmem_max = 65536



net.ipv4.tcp_fastopen = 3

net.ipv4.tcp_timestamps = 1

net.ipv4.tcp_tw_reuse = 1

net.ipv4.tcp_fin_timeout = 10

net.ipv4.tcp_slow_start_after_idle = 0

net.ipv4.tcp_max_tw_buckets = 32768

net.ipv4.tcp_sack = 1

net.ipv4.tcp_fack = 0



net.ipv4.tcp_rmem = 8192 87380 3939361

net.ipv4.tcp_wmem = 8192 65536 1969680

net.ipv4.tcp_mtu_probing = 1

net.ipv4.tcp_congestion_control = bbr

net.ipv4.tcp_notsent_lowat = 4096

net.ipv4.tcp_window_scaling = 1

net.ipv4.tcp_adv_win_scale = 4

net.ipv4.tcp_moderate_rcvbuf = 1

net.ipv4.tcp_no_metrics_save = 0



net.ipv4.tcp_max_syn_backlog = 2048

net.ipv4.tcp_max_orphans = 65536

net.ipv4.tcp_synack_retries = 2

net.ipv4.tcp_syn_retries = 3

net.ipv4.tcp_abort_on_overflow = 0

net.ipv4.tcp_stdurg = 0

net.ipv4.tcp_rfc1337 = 0

net.ipv4.tcp_syncookies = 1



net.ipv4.ip_local_port_range = 1024 65535

net.ipv4.ip_no_pmtu_disc = 0

net.ipv4.route.gc_timeout = 100

net.ipv4.neigh.default.gc_stale_time = 120

net.ipv4.neigh.default.gc_thresh3 = 8192

net.ipv4.neigh.default.gc_thresh2 = 4096

net.ipv4.neigh.default.gc_thresh1 = 1024



net.ipv4.icmp_echo_ignore_broadcasts = 1

net.ipv4.icmp_ignore_bogus_error_responses = 1

net.ipv4.conf.all.rp_filter = 1

net.ipv4.conf.default.rp_filter = 1

net.ipv4.conf.all.arp_announce = 2

net.ipv4.conf.default.arp_announce = 2

net.ipv4.conf.all.arp_ignore = 1

net.ipv4.conf.default.arp_ignore = 1" > /etc/sysctl.conf' && sudo sysctl -p

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 系统内核参数配置完成${NC}"
else
    echo -e "${RED}✗ 系统内核参数配置失败${NC}"
fi