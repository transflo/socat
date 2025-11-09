#!/bin/bash

# iptables 端口转发脚本（支持批量端口）
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

# 检查iptables是否安装
if ! command -v iptables &> /dev/null; then
    echo -e "${YELLOW}警告: 未检测到iptables，请先安装:${NC}"
    echo "  Ubuntu/Debian: sudo apt-get install -y iptables"
    echo "  CentOS/RHEL:   sudo yum install -y iptables"
    echo "  Arch Linux:    sudo pacman -S iptables"
    exit 1
fi

# 解析目标主机IP（如果是域名）
if [[ "$TARGET_HOST" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
    TARGET_IP=$TARGET_HOST
else
    echo -e "${YELLOW}解析目标主机域名: ${TARGET_HOST}${NC}"
    TARGET_IP=$(getent hosts ${TARGET_HOST} | awk '{ print $1 }' | head -n1)
    if [ -z "$TARGET_IP" ]; then
        echo -e "${RED}错误: 无法解析域名 ${TARGET_HOST}${NC}"
        exit 1
    fi
    echo -e "${GREEN}解析结果: ${TARGET_IP}${NC}"
fi

echo -e "${GREEN}开始创建iptables端口转发规则...${NC}"
echo -e "${BLUE}目标地址: ${TARGET_HOST} (${TARGET_IP})${NC}"
echo -e "${BLUE}端口列表: ${PORTS[*]}${NC}"
echo -e "${BLUE}共 ${#PORTS[@]} 个端口${NC}"
echo ""

# 启用IP转发
echo -e "${YELLOW}启用IP转发...${NC}"
if [ "$(sysctl -n net.ipv4.ip_forward)" != "1" ]; then
    sysctl -w net.ipv4.ip_forward=1 > /dev/null
    echo -e "${GREEN}✓ IP转发已启用${NC}"
else
    echo -e "${GREEN}✓ IP转发已启用（无需修改）${NC}"
fi

# 确保IP转发在重启后保持
if ! grep -q "^net.ipv4.ip_forward=1" /etc/sysctl.conf 2>/dev/null; then
    echo "net.ipv4.ip_forward=1" >> /etc/sysctl.conf
fi

# 检查并创建MASQUERADE规则（如果不存在）
if ! iptables -t nat -C POSTROUTING -j MASQUERADE 2>/dev/null; then
    echo -e "${YELLOW}添加MASQUERADE规则...${NC}"
    iptables -t nat -A POSTROUTING -j MASQUERADE
    echo -e "${GREEN}✓ MASQUERADE规则已添加${NC}"
fi

# 为每个端口创建iptables规则
RULES_CREATED=0
for LISTEN_PORT in "${PORTS[@]}"; do
    TARGET_PORT=$LISTEN_PORT  # 目标端口与监听端口相同
    
    echo -e "${YELLOW}[端口 ${LISTEN_PORT}] 创建转发规则...${NC}"
    
    # TCP转发规则
    if iptables -t nat -C PREROUTING -p tcp --dport ${LISTEN_PORT} -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT} 2>/dev/null; then
        echo -e "  ${YELLOW}TCP规则已存在，跳过${NC}"
    else
        iptables -t nat -A PREROUTING -p tcp --dport ${LISTEN_PORT} -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT}
        echo -e "  ${GREEN}✓ TCP转发规则已创建${NC}"
        RULES_CREATED=1
    fi
    
    # UDP转发规则
    if iptables -t nat -C PREROUTING -p udp --dport ${LISTEN_PORT} -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT} 2>/dev/null; then
        echo -e "  ${YELLOW}UDP规则已存在，跳过${NC}"
    else
        iptables -t nat -A PREROUTING -p udp --dport ${LISTEN_PORT} -j DNAT --to-destination ${TARGET_IP}:${TARGET_PORT}
        echo -e "  ${GREEN}✓ UDP转发规则已创建${NC}"
        RULES_CREATED=1
    fi
    
    # FORWARD链规则（允许转发）
    if ! iptables -C FORWARD -p tcp -d ${TARGET_IP} --dport ${TARGET_PORT} -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -p tcp -d ${TARGET_IP} --dport ${TARGET_PORT} -j ACCEPT
    fi
    if ! iptables -C FORWARD -p udp -d ${TARGET_IP} --dport ${TARGET_PORT} -j ACCEPT 2>/dev/null; then
        iptables -A FORWARD -p udp -d ${TARGET_IP} --dport ${TARGET_PORT} -j ACCEPT
    fi
done

# 保存iptables规则
if [ $RULES_CREATED -eq 1 ]; then
    echo ""
    echo -e "${YELLOW}保存iptables规则...${NC}"
    
    # 检测系统类型并保存规则
    if command -v iptables-save &> /dev/null; then
        if [ -d /etc/iptables ]; then
            iptables-save > /etc/iptables/rules.v4
            echo -e "${GREEN}✓ 规则已保存到 /etc/iptables/rules.v4${NC}"
        elif [ -f /etc/network/iptables.rules ]; then
            iptables-save > /etc/network/iptables.rules
            echo -e "${GREEN}✓ 规则已保存到 /etc/network/iptables.rules${NC}"
        else
            # 尝试创建保存目录
            mkdir -p /etc/iptables
            iptables-save > /etc/iptables/rules.v4
            echo -e "${GREEN}✓ 规则已保存到 /etc/iptables/rules.v4${NC}"
            
            # 创建systemd服务以在启动时恢复规则
            if [ ! -f /etc/systemd/system/iptables-restore.service ]; then
                cat > /etc/systemd/system/iptables-restore.service <<EOF
[Unit]
Description=Restore iptables rules
After=network.target

[Service]
Type=oneshot
ExecStart=/sbin/iptables-restore /etc/iptables/rules.v4
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
                systemctl daemon-reload
                systemctl enable iptables-restore.service > /dev/null 2>&1
                echo -e "${GREEN}✓ 已创建iptables自动恢复服务${NC}"
            fi
        fi
    else
        echo -e "${YELLOW}警告: 未找到iptables-save命令，规则未保存${NC}"
        echo -e "${YELLOW}请手动保存规则或安装iptables-persistent${NC}"
    fi
fi

# 检查规则状态
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}所有转发规则创建完成！${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示每个端口的规则状态
for LISTEN_PORT in "${PORTS[@]}"; do
    echo -e "${BLUE}端口 ${LISTEN_PORT}:${NC}"
    
    # 检查TCP规则
    if iptables -t nat -C PREROUTING -p tcp --dport ${LISTEN_PORT} -j DNAT --to-destination ${TARGET_IP}:${LISTEN_PORT} 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} TCP转发: ${LISTEN_PORT} -> ${TARGET_IP}:${LISTEN_PORT}"
    else
        echo -e "  ${RED}✗${NC} TCP转发规则不存在"
    fi
    
    # 检查UDP规则
    if iptables -t nat -C PREROUTING -p udp --dport ${LISTEN_PORT} -j DNAT --to-destination ${TARGET_IP}:${LISTEN_PORT} 2>/dev/null; then
        echo -e "  ${GREEN}✓${NC} UDP转发: ${LISTEN_PORT} -> ${TARGET_IP}:${LISTEN_PORT}"
    else
        echo -e "  ${RED}✗${NC} UDP转发规则不存在"
    fi
    echo ""
done

echo "常用命令:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "查看所有NAT规则:"
echo "  iptables -t nat -L -n -v"
echo ""
echo "查看特定端口规则:"
for LISTEN_PORT in "${PORTS[@]}"; do
    echo "  端口 ${LISTEN_PORT}:"
    echo "    iptables -t nat -L PREROUTING -n -v | grep ${LISTEN_PORT}"
done
echo ""
echo "删除转发规则（示例，端口 ${PORTS[0]}）:"
echo "  iptables -t nat -D PREROUTING -p tcp --dport ${PORTS[0]} -j DNAT --to-destination ${TARGET_IP}:${PORTS[0]}"
echo "  iptables -t nat -D PREROUTING -p udp --dport ${PORTS[0]} -j DNAT --to-destination ${TARGET_IP}:${PORTS[0]}"
echo ""
echo "保存当前规则:"
echo "  iptables-save > /etc/iptables/rules.v4"
echo ""
echo "恢复规则:"
echo "  iptables-restore < /etc/iptables/rules.v4"
echo ""

# 配置系统内核参数
echo -e "${YELLOW}配置系统内核参数...${NC}"
cp /etc/sysctl.conf /etc/sysctl.conf.bk_$(date +%Y%m%d_%H%M%S)
cat > /etc/sysctl.conf << 'SYSCTL_EOF'
kernel.pid_max = 65535

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

net.ipv4.conf.default.arp_ignore = 1
SYSCTL_EOF

sysctl -p > /dev/null 2>&1
if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ 系统内核参数配置完成${NC}"
else
    echo -e "${RED}✗ 系统内核参数配置失败${NC}"
fi
