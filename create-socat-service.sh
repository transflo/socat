#!/bin/bash

# Realm 端口转发脚本（支持批量端口）
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

# 检查realm是否安装
if ! command -v realm &> /dev/null; then
    echo -e "${YELLOW}未检测到realm，正在安装...${NC}"
    
    # 检测系统架构
    ARCH=$(uname -m)
    case ${ARCH} in
        x86_64)
            REALM_ARCH="x86_64"
            ;;
        aarch64|arm64)
            REALM_ARCH="aarch64"
            ;;
        armv7l)
            REALM_ARCH="armv7"
            ;;
        *)
            echo -e "${RED}错误: 不支持的系统架构 ${ARCH}${NC}"
            exit 1
            ;;
    esac
    
    # 下载最新版realm
    REALM_VERSION="2.6.1"
    
    # 定义多个下载源（包括国内镜像）
    DOWNLOAD_URLS=(
        "https://edgecname.gh-proxy.com/https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        "https://ghproxy.com/https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        "https://github.moeyy.xyz/https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        "https://gh.ddlc.top/https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        "https://mirror.ghproxy.com/https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        "https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
    )
    
    echo -e "${YELLOW}正在下载 realm ${REALM_VERSION} (${REALM_ARCH})...${NC}"
    
    TMP_DIR=$(mktemp -d)
    cd ${TMP_DIR}
    
    # 尝试从多个源下载
    DOWNLOAD_SUCCESS=0
    for i in "${!DOWNLOAD_URLS[@]}"; do
        DOWNLOAD_URL="${DOWNLOAD_URLS[$i]}"
        echo -e "${BLUE}尝试下载源 $((i+1))/${#DOWNLOAD_URLS[@]}...${NC}"
        
        if wget --timeout=30 --tries=2 -q --show-progress "${DOWNLOAD_URL}" -O realm.tar.gz 2>/dev/null; then
            # 验证下载的文件
            if [ -f realm.tar.gz ] && [ -s realm.tar.gz ]; then
                echo -e "${GREEN}✓ 下载成功！${NC}"
                DOWNLOAD_SUCCESS=1
                break
            else
                echo -e "${YELLOW}  下载的文件无效，尝试下一个源...${NC}"
                rm -f realm.tar.gz
            fi
        else
            echo -e "${YELLOW}  下载失败，尝试下一个源...${NC}"
        fi
    done
    
    if [ $DOWNLOAD_SUCCESS -eq 0 ]; then
        echo ""
        echo -e "${RED}所有下载源都失败了！${NC}"
        echo -e "${YELLOW}请尝试以下方法手动安装 realm:${NC}"
        echo ""
        echo "方法1: 从官方仓库下载"
        echo "  访问: https://github.com/zhboner/realm/releases"
        echo "  下载: realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        echo ""
        echo "方法2: 使用代理下载"
        echo "  export http_proxy=http://your-proxy:port"
        echo "  export https_proxy=http://your-proxy:port"
        echo "  然后重新运行此脚本"
        echo ""
        echo "方法3: 手动安装"
        echo "  1. 下载文件到本地"
        echo "  2. 执行以下命令:"
        echo "     tar -xzf realm-${REALM_ARCH}-unknown-linux-musl.tar.gz"
        echo "     sudo mv realm /usr/local/bin/"
        echo "     sudo chmod +x /usr/local/bin/realm"
        echo ""
        echo "方法4: 使用 curl 下载（如果可用）"
        echo "  curl -L https://github.com/zhboner/realm/releases/download/v${REALM_VERSION}/realm-${REALM_ARCH}-unknown-linux-musl.tar.gz -o realm.tar.gz"
        echo ""
        rm -rf ${TMP_DIR}
        exit 1
    fi
    
    # 解压并安装
    echo -e "${YELLOW}正在安装 realm...${NC}"
    if ! tar -xzf realm.tar.gz 2>/dev/null; then
        echo -e "${RED}解压失败，文件可能已损坏${NC}"
        rm -rf ${TMP_DIR}
        exit 1
    fi
    
    if [ ! -f realm ]; then
        echo -e "${RED}错误: 解压后未找到 realm 可执行文件${NC}"
        rm -rf ${TMP_DIR}
        exit 1
    fi
    
    mv realm /usr/local/bin/
    chmod +x /usr/local/bin/realm
    
    rm -rf ${TMP_DIR}
    
    if command -v realm &> /dev/null; then
        echo -e "${GREEN}✓ realm 安装成功！${NC}"
        realm --version
    else
        echo -e "${RED}✗ realm 安装失败${NC}"
        exit 1
    fi
fi

echo -e "${GREEN}开始创建 Realm 端口转发服务...${NC}"
echo -e "${BLUE}目标地址: ${TARGET_HOST}${NC}"
echo -e "${BLUE}端口列表: ${PORTS[*]}${NC}"
echo -e "${BLUE}共 ${#PORTS[@]} 个端口${NC}"
echo ""

# 为每个端口创建realm服务
SERVICES_CREATED=0
for LISTEN_PORT in "${PORTS[@]}"; do
    TARGET_PORT=$LISTEN_PORT  # 目标端口与监听端口相同
    SERVICE_NAME="realm-forward-${LISTEN_PORT}"
    
    echo -e "${YELLOW}[端口 ${LISTEN_PORT}] 创建转发服务...${NC}"
    
    # 停止现有服务（如果存在）
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        systemctl stop ${SERVICE_NAME}
        echo -e "  ${YELLOW}已停止现有服务${NC}"
    fi
    
    # 创建systemd服务文件
    cat > /etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Realm Port Forward ${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}
After=network.target
Wants=network.target

[Service]
Type=simple
ExecStart=/usr/local/bin/realm -l 0.0.0.0:${LISTEN_PORT} -r ${TARGET_HOST}:${TARGET_PORT}
Restart=always
RestartSec=3
User=root
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
    
    # 重新加载systemd配置
    systemctl daemon-reload
    
    # 启动并启用服务
    systemctl enable ${SERVICE_NAME} > /dev/null 2>&1
    systemctl start ${SERVICE_NAME}
    
    # 检查服务状态
    sleep 1
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "  ${GREEN}✓ 服务已创建并启动: ${SERVICE_NAME}${NC}"
        echo -e "  ${GREEN}✓ 转发: 0.0.0.0:${LISTEN_PORT} -> ${TARGET_HOST}:${TARGET_PORT}${NC}"
        SERVICES_CREATED=$((SERVICES_CREATED + 1))
    else
        echo -e "  ${RED}✗ 服务启动失败: ${SERVICE_NAME}${NC}"
        echo -e "  ${YELLOW}查看日志: journalctl -u ${SERVICE_NAME} -n 20${NC}"
    fi
    echo ""
done

# 检查服务状态
echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}所有转发服务创建完成！${NC}"
echo -e "${GREEN}成功创建 ${SERVICES_CREATED}/${#PORTS[@]} 个服务${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

# 显示每个端口的服务状态
echo -e "${BLUE}服务状态:${NC}"
for LISTEN_PORT in "${PORTS[@]}"; do
    SERVICE_NAME="realm-forward-${LISTEN_PORT}"
    echo -e "\n${BLUE}端口 ${LISTEN_PORT}:${NC}"
    
    if systemctl is-active --quiet ${SERVICE_NAME}; then
        echo -e "  ${GREEN}✓${NC} 服务运行中: ${SERVICE_NAME}"
        echo -e "  ${GREEN}✓${NC} 转发: 0.0.0.0:${LISTEN_PORT} -> ${TARGET_HOST}:${LISTEN_PORT}"
    else
        echo -e "  ${RED}✗${NC} 服务未运行: ${SERVICE_NAME}"
    fi
done

echo ""
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "常用命令:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "查看所有realm转发服务:"
echo "  systemctl list-units 'realm-forward-*' --all"
echo ""
echo "查看特定端口服务:"
for LISTEN_PORT in "${PORTS[@]}"; do
    echo "  端口 ${LISTEN_PORT}:"
    echo "    systemctl status realm-forward-${LISTEN_PORT}"
    echo "    journalctl -u realm-forward-${LISTEN_PORT} -f"
done
echo ""
echo "重启服务（示例，端口 ${PORTS[0]}）:"
echo "  systemctl restart realm-forward-${PORTS[0]}"
echo ""
echo "停止服务（示例，端口 ${PORTS[0]}）:"
echo "  systemctl stop realm-forward-${PORTS[0]}"
echo ""
echo "删除服务（示例，端口 ${PORTS[0]}）:"
echo "  systemctl stop realm-forward-${PORTS[0]}"
echo "  systemctl disable realm-forward-${PORTS[0]}"
echo "  rm -f /etc/systemd/system/realm-forward-${PORTS[0]}.service"
echo "  systemctl daemon-reload"
echo ""
echo "查看所有监听端口:"
echo "  ss -tlnp | grep realm"
echo ""
echo "手动测试转发（示例，端口 ${PORTS[0]}）:"
echo "  realm -l 0.0.0.0:${PORTS[0]} -r ${TARGET_HOST}:${PORTS[0]}"
echo ""

# 配置系统内核参数（优化网络性能）
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

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}配置完成！所有转发服务已启动并设置为开机自启${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
