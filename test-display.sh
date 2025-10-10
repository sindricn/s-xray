#!/bin/bash

# 测试主菜单显示效果

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# 模拟数据
version="v1.8.8"
status="${GREEN}运行中${NC}"
node_count=3
user_count=5

clear

echo -e "${CYAN}╔═══════════════════════════════════════╗${NC}"
echo -e "${CYAN}║    Xray-Core 一键管理脚本 v1.2.1    ║${NC}"
echo -e "${CYAN}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}┌─────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  ${YELLOW}系统状态${NC}                           ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}  内核版本: ${YELLOW}${version}${NC}"
echo -e "${CYAN}│${NC}  运行状态: ${status}"
echo -e "${CYAN}│${NC}  节点数量: ${BLUE}${node_count}${NC}"
echo -e "${CYAN}│${NC}  用户数量: ${BLUE}${user_count}${NC}"
echo -e "${CYAN}└─────────────────────────────────────┘${NC}"
echo ""
echo -e "${CYAN}┌─────────────────────────────────────┐${NC}"
echo -e "${CYAN}│${NC}  ${YELLOW}功能菜单${NC}                           ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}1.${NC}  内核管理                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}2.${NC}  节点管理                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}3.${NC}  用户管理                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}4.${NC}  订阅管理                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}5.${NC}  防火墙管理                     ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}6.${NC}  配置管理                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}7.${NC}  域名管理                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}8.${NC}  证书管理                       ${CYAN}│${NC}"
echo -e "${CYAN}├─────────────────────────────────────┤${NC}"
echo -e "${CYAN}│${NC}  ${RED}9.${NC}  卸载脚本                       ${CYAN}│${NC}"
echo -e "${CYAN}│${NC}  ${GREEN}0.${NC}  退出脚本                       ${CYAN}│${NC}"
echo -e "${CYAN}└─────────────────────────────────────┘${NC}"
echo ""

echo -e "${GREEN}✓ 显示测试完成！${NC}"
echo ""
echo -e "${YELLOW}主要改进：${NC}"
echo -e "  1. ✅ 移除了格式化符号（%-23s等）的显示问题"
echo -e "  2. ✅ 卸载选项编号从99改为9"
echo -e "  3. ✅ 系统状态和功能菜单标题使用黄色高亮"
echo -e "  4. ✅ 版本号更新为 v1.2.1"
echo ""

# 测试卸载界面
echo -e "${YELLOW}按 Enter 查看卸载界面...${NC}"
read

clear
echo -e "${RED}╔═══════════════════════════════════════╗${NC}"
echo -e "${RED}║          警告：卸载脚本              ║${NC}"
echo -e "${RED}╚═══════════════════════════════════════╝${NC}"
echo ""
echo -e "${YELLOW}此操作将卸载 s-xray 管理脚本${NC}"
echo -e "${YELLOW}包括所有配置文件和数据${NC}"
echo ""
echo -e "${GREEN}✓ 卸载界面显示测试完成！${NC}"
echo ""
