#!/usr/bin/env python3
"""
JSON 操作辅助脚本
用于替代复杂的 jq 操作，避免 Bash 变量传递 JSON 的编码问题
"""

import json
import sys
from datetime import datetime, timezone
from pathlib import Path


def load_json(file_path):
    """加载 JSON 文件"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            return json.load(f)
    except FileNotFoundError:
        return None
    except json.JSONDecodeError as e:
        print(f"JSON 格式错误: {file_path}", file=sys.stderr)
        print(f"错误详情: {e}", file=sys.stderr)
        sys.exit(1)


def save_json(data, file_path):
    """保存 JSON 文件"""
    try:
        with open(file_path, 'w', encoding='utf-8') as f:
            json.dump(data, f, ensure_ascii=False, indent=2)
    except Exception as e:
        print(f"写入 JSON 失败: {file_path}", file=sys.stderr)
        print(f"错误详情: {e}", file=sys.stderr)
        sys.exit(1)


def add_user(file_path, user_id, username, password, email, level=0,
             traffic_limit="unlimited", expire_date="unlimited"):
    """添加用户"""
    data = load_json(file_path) or {"users": []}

    # 检查用户是否已存在
    for user in data.get("users", []):
        if user.get("username") == username:
            print(f"用户已存在: {username}", file=sys.stderr)
            sys.exit(1)

    # 添加新用户
    new_user = {
        "id": user_id,
        "username": username,
        "password": password,
        "email": email,
        "level": level,
        "traffic_limit_gb": traffic_limit,
        "traffic_used_gb": "0",
        "expire_date": expire_date,
        "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "enabled": True
    }

    data.setdefault("users", []).append(new_user)
    save_json(data, file_path)
    print("用户添加成功")


def update_user(file_path, username, **updates):
    """更新用户信息"""
    data = load_json(file_path)
    if not data:
        print("用户文件不存在", file=sys.stderr)
        sys.exit(1)

    found = False
    for user in data.get("users", []):
        if user.get("username") == username:
            user.update(updates)
            found = True
            break

    if not found:
        print(f"用户不存在: {username}", file=sys.stderr)
        sys.exit(1)

    save_json(data, file_path)
    print("用户更新成功")


def delete_user(file_path, username):
    """删除用户"""
    data = load_json(file_path)
    if not data:
        print("用户文件不存在", file=sys.stderr)
        sys.exit(1)

    original_count = len(data.get("users", []))
    data["users"] = [u for u in data.get("users", []) if u.get("username") != username]

    if len(data["users"]) == original_count:
        print(f"用户不存在: {username}", file=sys.stderr)
        sys.exit(1)

    save_json(data, file_path)
    print("用户删除成功")


def add_node(file_path, name, protocol, port, transport, security, extra_json):
    """添加节点

    Args:
        file_path: 节点JSON文件路径
        name: 节点名称
        protocol: 协议类型
        port: 端口号
        transport: 传输方式
        security: 安全类型
        extra_json: 额外配置JSON字符串
    """
    data = load_json(file_path) or {"nodes": []}

    # 解析 extra 参数（JSON 字符串）
    try:
        extra = json.loads(extra_json)
    except json.JSONDecodeError as e:
        print(f"额外配置JSON格式错误: {e}", file=sys.stderr)
        sys.exit(1)

    new_node = {
        "name": name,
        "protocol": protocol,
        "port": port,
        "transport": transport,
        "security": security,
        "extra": extra,
        "created": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    }

    data.setdefault("nodes", []).append(new_node)
    save_json(data, file_path)
    print("节点添加成功")


def main():
    """命令行接口"""
    if len(sys.argv) < 3:
        print("用法: json_helper.py <操作> <文件> [参数...]", file=sys.stderr)
        print("操作: add_user, update_user, delete_user, add_node", file=sys.stderr)
        sys.exit(1)

    operation = sys.argv[1]
    file_path = sys.argv[2]
    args = sys.argv[3:]

    try:
        if operation == "add_user":
            # add_user <file> <id> <username> <password> <email> [level] [traffic] [expire]
            add_user(file_path, args[0], args[1], args[2], args[3],
                    int(args[4]) if len(args) > 4 else 0,
                    args[5] if len(args) > 5 else "unlimited",
                    args[6] if len(args) > 6 else "unlimited")

        elif operation == "update_user":
            # update_user <file> <username> <field> <value> [field2] [value2] ...
            username = args[0]
            updates = {}
            for i in range(1, len(args), 2):
                if i+1 < len(args):
                    field = args[i]
                    value = args[i+1]
                    # 类型转换
                    if value.lower() == 'true':
                        value = True
                    elif value.lower() == 'false':
                        value = False
                    elif field == 'level' and value.isdigit():
                        value = int(value)
                    updates[field] = value
            update_user(file_path, username, **updates)

        elif operation == "delete_user":
            # delete_user <file> <username>
            delete_user(file_path, args[0])

        elif operation == "add_node":
            # add_node <file> <name> <protocol> <port> <transport> <security> <extra_json>
            add_node(file_path, args[0], args[1], args[2], args[3], args[4], args[5])

        else:
            print(f"未知操作: {operation}", file=sys.stderr)
            sys.exit(1)

    except IndexError:
        print("参数不足", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"操作失败: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
