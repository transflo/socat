#!/bin/bash

###############################################################################
# VPS流量限速脚本
# 功能：自动检测流量最大的网络接口，并进行上下行限速
# 使用：./traffic_limit.sh [选项]
###############################################################################

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 显示帮助信息
show_help() {
    cat << EOF
VPS流量限速脚本

用法:
    $0 -u <上行速率> -d <下行速率> [选项]

参数:
    -u, --upload <速率>     上行限速（Mbps）
    -d, --download <速率>   下行限速（Mbps）
    -i, --interface <接口>  指定网络接口（可选，不指定则自动检测流量最大的接口）
    -c, --clear             清除所有限速设置
    -s, --status            显示当前限速状态
    -h, --help              显示此帮助信息

示例:
    # 自动检测接口并限速为上行10Mbps，下行20Mbps
    $0 -u 10 -d 20

    # 指定eth0接口限速
    $0 -i eth0 -u 10 -d 20

    # 清除所有限速
    $0 -c

    # 查看当前限速状态
    $0 -s

注意:
    - 需要root权限运行
    - 需要安装iproute2包（tc命令）
    - 速率单位为Mbps

EOF
}

# 检查root权限
check_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${RED}错误: 请使用root权限运行此脚本${NC}"
        echo "使用: sudo $0"
        exit 1
    fi
}

# 检查必要的命令
check_requirements() {
    local missing_cmds=()
    
    for cmd in tc ip awk; do
        if ! command -v $cmd &> /dev/null; then
            missing_cmds+=($cmd)
        fi
    done
    
    if [ ${#missing_cmds[@]} -ne 0 ]; then
        echo -e "${RED}错误: 缺少必要的命令: ${missing_cmds[*]}${NC}"
        echo "请安装iproute2包:"
        echo "  Ubuntu/Debian: apt-get install iproute2"
        echo "  CentOS/RHEL: yum install iproute"
        exit 1
    fi
}

# 获取所有活动的网络接口
get_active_interfaces() {
    ip -o link show | awk -F': ' '{print $2}' | grep -v "lo" | sed 's/@.*//'
}

# 获取指定接口的流量统计（字节数）
get_interface_traffic() {
    local interface=$1
    local rx_bytes=$(cat /sys/class/net/$interface/statistics/rx_bytes 2>/dev/null || echo 0)
    local tx_bytes=$(cat /sys/class/net/$interface/statistics/tx_bytes 2>/dev/null || echo 0)
    echo $((rx_bytes + tx_bytes))
}

# 检测流量最大的网络接口
detect_busiest_interface() {
    echo -e "${YELLOW}正在检测流量最大的网络接口...${NC}" >&2
    
    local interfaces=($(get_active_interfaces))
    
    if [ ${#interfaces[@]} -eq 0 ]; then
        echo -e "${RED}错误: 未找到活动的网络接口${NC}" >&2
        exit 1
    fi
    
    # 第一次采样
    declare -A traffic1
    for iface in "${interfaces[@]}"; do
        traffic1[$iface]=$(get_interface_traffic $iface)
    done
    
    # 等待1秒
    sleep 1
    
    # 第二次采样并计算差值
    local max_traffic=0
    local busiest_iface=""
    
    for iface in "${interfaces[@]}"; do
        local traffic2=$(get_interface_traffic $iface)
        local diff=$((traffic2 - traffic1[$iface]))
        
        if [ $diff -gt $max_traffic ]; then
            max_traffic=$diff
            busiest_iface=$iface
        fi
    done
    
    if [ -z "$busiest_iface" ]; then
        # 如果没有流量，选择第一个接口
        busiest_iface=${interfaces[0]}
    fi
    
    echo -e "${GREEN}检测到流量最大的接口: $busiest_iface${NC}" >&2
    echo "$busiest_iface"
}

# 清除指定接口的限速设置
clear_limit() {
    local interface=$1
    
    # 清除根qdisc
    tc qdisc del dev $interface root 2>/dev/null
    tc qdisc del dev $interface ingress 2>/dev/null
    
    # 删除ifb设备（如果存在）
    if ip link show ifb0 &>/dev/null; then
        ip link set dev ifb0 down 2>/dev/null
        ip link delete ifb0 type ifb 2>/dev/null
    fi
}

# 清除所有接口的限速
clear_all_limits() {
    echo -e "${YELLOW}正在清除所有网络接口的限速设置...${NC}"
    
    local interfaces=($(get_active_interfaces))
    
    for iface in "${interfaces[@]}"; do
        clear_limit $iface
        echo "已清除接口 $iface 的限速设置"
    done
    
    echo -e "${GREEN}所有限速设置已清除${NC}"
}

# 显示当前限速状态
show_status() {
    echo -e "${YELLOW}=== 当前网络限速状态 ===${NC}"
    echo ""
    
    local interfaces=($(get_active_interfaces))
    local has_limit=0
    
    for iface in "${interfaces[@]}"; do
        if tc qdisc show dev $iface | grep -q "htb\|tbf"; then
            echo -e "${GREEN}接口: $iface${NC}"
            echo "限速配置:"
            tc qdisc show dev $iface | sed 's/^/  /'
            echo ""
            has_limit=1
        fi
    done
    
    if [ $has_limit -eq 0 ]; then
        echo "当前没有任何限速设置"
    fi
}

# 应用限速设置
apply_limit() {
    local interface=$1
    local upload_mbps=$2
    local download_mbps=$3
    
    echo -e "${YELLOW}正在对接口 $interface 应用限速设置...${NC}"
    
    # 检查接口是否存在
    if ! ip link show $interface &>/dev/null; then
        echo -e "${RED}错误: 网络接口 $interface 不存在${NC}"
        exit 1
    fi
    
    # 清除现有设置
    clear_limit $interface
    
    # 转换Mbps到kbit
    local upload_kbit=$((upload_mbps * 1024))
    local download_kbit=$((download_mbps * 1024))
    
    echo "  上行限速: ${upload_mbps}Mbps (${upload_kbit}kbit)"
    echo "  下行限速: ${download_mbps}Mbps (${download_kbit}kbit)"
    
    # 设置上行限速（egress）
    tc qdisc add dev $interface root handle 1: htb default 10
    tc class add dev $interface parent 1: classid 1:1 htb rate ${upload_kbit}kbit
    tc class add dev $interface parent 1:1 classid 1:10 htb rate ${upload_kbit}kbit
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 上行限速设置失败${NC}"
        exit 1
    fi
    
    # 设置下行限速（ingress）- 使用ifb设备
    # 加载ifb模块
    modprobe ifb numifbs=1 2>/dev/null
    
    # 创建并启用ifb0设备
    ip link add ifb0 type ifb 2>/dev/null
    ip link set dev ifb0 up
    
    # 重定向ingress流量到ifb0
    tc qdisc add dev $interface handle ffff: ingress
    tc filter add dev $interface parent ffff: protocol ip u32 match u32 0 0 action mirred egress redirect dev ifb0
    
    # 在ifb0上设置egress限速（实际是原接口的ingress限速）
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1: classid 1:1 htb rate ${download_kbit}kbit
    tc class add dev ifb0 parent 1:1 classid 1:10 htb rate ${download_kbit}kbit
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}错误: 下行限速设置失败${NC}"
        clear_limit $interface
        exit 1
    fi
    
    echo -e "${GREEN}限速设置成功！${NC}"
    echo ""
    echo "接口: $interface"
    echo "上行限速: ${upload_mbps}Mbps"
    echo "下行限速: ${download_mbps}Mbps"
}

# 主函数
main() {
    local upload_speed=""
    local download_speed=""
    local interface=""
    local clear_mode=0
    local status_mode=0
    
    # 解析命令行参数
    while [[ $# -gt 0 ]]; do
        case $1 in
            -u|--upload)
                upload_speed="$2"
                shift 2
                ;;
            -d|--download)
                download_speed="$2"
                shift 2
                ;;
            -i|--interface)
                interface="$2"
                shift 2
                ;;
            -c|--clear)
                clear_mode=1
                shift
                ;;
            -s|--status)
                status_mode=1
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                echo -e "${RED}错误: 未知参数 $1${NC}"
                show_help
                exit 1
                ;;
        esac
    done
    
    # 检查权限和依赖
    check_root
    check_requirements
    
    # 清除模式
    if [ $clear_mode -eq 1 ]; then
        clear_all_limits
        exit 0
    fi
    
    # 状态查看模式
    if [ $status_mode -eq 1 ]; then
        show_status
        exit 0
    fi
    
    # 验证必需参数
    if [ -z "$upload_speed" ] || [ -z "$download_speed" ]; then
        echo -e "${RED}错误: 必须指定上行和下行速率${NC}"
        echo ""
        show_help
        exit 1
    fi
    
    # 验证速率是否为正整数
    if ! [[ "$upload_speed" =~ ^[0-9]+$ ]] || ! [[ "$download_speed" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}错误: 速率必须为正整数${NC}"
        exit 1
    fi
    
    # 如果未指定接口，自动检测
    if [ -z "$interface" ]; then
        interface=$(detect_busiest_interface)
    else
        echo -e "${GREEN}使用指定接口: $interface${NC}"
    fi
    
    # 应用限速
    apply_limit "$interface" "$upload_speed" "$download_speed"
}

# 运行主函数
main "$@"

