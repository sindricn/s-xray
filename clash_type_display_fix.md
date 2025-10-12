# Clash 订阅类型显示修复

## 问题描述
生成 Clash 订阅后，订阅类型显示为"未知类型"而不是"Clash订阅 (YAML)"

## 原因
`get_sub_type_name()` 函数只处理了类型 1（通用订阅）和类型 2（原始订阅），缺少类型 3（Clash订阅）的处理。

## 修复内容

### 1. 添加 Clash 类型名称 (Line 1142)

**文件**: `modules/subscription.sh`

```bash
get_sub_type_name() {
    case $1 in
        1) echo "通用订阅 (Base64)" ;;
        2) echo "原始订阅 (纯文本)" ;;
        3) echo "Clash订阅 (YAML)" ;;      # 新增
        *) echo "未知类型" ;;
    esac
}
```

### 2. 添加 Clash 客户端列表 (Line 1133-1144)

```bash
3)
    echo -e "${CYAN}支持的客户端（推荐）：${NC}"
    echo -e "  • Clash Verge (推荐) - 跨平台"
    echo -e "  • Clash Verge Rev - 社区维护版"
    echo -e "  • Clash Meta - 核心版本"
    echo -e "  • Clash Nyanpasu - 新一代客户端"
    echo -e "  • Clash for Android - 需 Meta 核心"
    echo ""
    echo -e "${YELLOW}注意：${NC}"
    echo -e "  • Reality 节点需要 Clash Meta 内核支持"
    echo -e "  • 不支持原版 Clash Premium"
    ;;
```

## 修复效果

### 修复前
```
订阅信息：
  订阅名称: test-clash
  绑定用户: admin
  节点数量: 3
  订阅类型: 未知类型        ← 显示错误

订阅链接：
http://1.2.3.4:8080/sub/test-clash_clash.yaml
```

### 修复后
```
订阅信息：
  订阅名称: test-clash
  绑定用户: admin
  节点数量: 3
  订阅类型: Clash订阅 (YAML)    ← 正确显示

订阅链接：
http://1.2.3.4:8080/sub/test-clash_clash.yaml

支持的客户端（推荐）：
  • Clash Verge (推荐) - 跨平台
  • Clash Verge Rev - 社区维护版
  • Clash Meta - 核心版本
  • Clash Nyanpasu - 新一代客户端
  • Clash for Android - 需 Meta 核心

注意：
  • Reality 节点需要 Clash Meta 内核支持
  • 不支持原版 Clash Premium
```

## 订阅类型对照表

| 类型值 | 名称 | 格式 | 客户端 |
|--------|------|------|--------|
| 1 | 通用订阅 (Base64) | Base64 编码 | V2RayN, Shadowrocket, QX |
| 2 | 原始订阅 (纯文本) | 纯文本链接 | 所有客户端 |
| 3 | Clash订阅 (YAML) | YAML 配置 | Clash Meta 系列 |

## 文件修改

**modules/subscription.sh**:
- Line 1142: 添加 Clash 类型名称
- Line 1133-1144: 添加 Clash 客户端支持列表

## 测试验证

生成 Clash 订阅后应该看到：
- ✅ 订阅类型正确显示为"Clash订阅 (YAML)"
- ✅ 显示推荐的 Clash Meta 客户端列表
- ✅ 提示 Reality 节点需要 Meta 内核

---

**修复完成时间**: 2025-10-12
**影响范围**: 显示内容优化，不影响功能
