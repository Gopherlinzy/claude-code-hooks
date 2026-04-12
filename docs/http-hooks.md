# HTTP Hooks 配置指南

## 概述
Claude Code Hooks 支持 `command` 类型的 hook，可通过 shell 命令发起 HTTP 请求实现远程回调通知。

## 配置格式

在 `~/.claude/settings.json` 的 `hooks` 字段中配置：

```json
{
  "hooks": {
    "<HookEvent>": [
      {
        "matcher": "<匹配规则>",
        "hooks": [
          {
            "type": "command",
            "command": "curl -s -X POST http://your-server:port/api/endpoint -H 'Content-Type: application/json' -d '{\"event\":\"hook_fired\"}'",
            "timeout": 10
          }
        ]
      }
    ]
  }
}
```

## Hook 事件类型

| 事件 | 触发时机 | 典型用途 |
|------|---------|---------|
| `PreToolUse` | 工具调用前 | 安全拦截、审批 |
| `PostToolUse` | 工具调用后 | 日志记录、通知 |
| `Stop` | 会话结束时 | 完成回调 |
| `UserPromptSubmit` | 用户提交 prompt 时 | 输入审计 |
| `PostToolUseFailure` | 工具调用失败时 | 错误告警 |
| `PermissionRequest` | 权限请求时 | 审批通知 |

## matcher 规则

- 空字符串 `""`: 匹配所有
- 通配符 `"*"`: 匹配所有
- 工具名: `"Bash"`、`"Read|Edit|Write"`（用 `|` 分隔多个）

## 示例

### 1. Stop 事件 — 任务完成通知

```json
{
  "matcher": "",
  "hooks": [
    {
      "type": "command",
      "command": "curl -s -X POST http://127.0.0.1:YOUR_GATEWAY_PORT/api/cron/wake -H 'Content-Type: application/json' -d \"{\\\"task_id\\\":\\\"${CLAUDE_TASK_ID:-unknown}\\\"}\"",
      "timeout": 10
    }
  ]
}
```

### 2. PreToolUse — 远程审批网关

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); curl -s -X POST http://127.0.0.1:YOUR_GATEWAY_PORT/api/hooks/approve -H 'Content-Type: application/json' -d \"$INPUT\"",
      "timeout": 15
    }
  ]
}
```

远程服务返回 JSON 决策：
- 放行: `{}` 或不输出（exit 0）
- 拒绝: `{"decision":"deny","reason":"不允许执行此操作"}`

### 3. PostToolUse — 操作日志上报

```json
{
  "matcher": "*",
  "hooks": [
    {
      "type": "command",
      "command": "INPUT=$(cat); curl -s -X POST http://127.0.0.1:YOUR_GATEWAY_PORT/api/hooks/log -H 'Content-Type: application/json' -d \"$INPUT\" || true",
      "timeout": 5
    }
  ]
}
```

## 注意事项

1. **超时设置**: `timeout` 单位为秒，建议 HTTP hook 设置 5-15 秒，避免阻塞 Claude Code
2. **容错处理**: 命令末尾加 `|| true` 防止网络异常导致 hook 失败阻塞会话
3. **环境变量**: hook 命令中可使用 `CLAUDE_TASK_ID`、`CLAUDE_TASK_NAME` 等环境变量
4. **安全**: 避免在 hook 命令中硬编码敏感信息，使用环境变量传递
5. **PreToolUse 决策**: 若 hook 输出包含 `{"decision":"deny",...}` 则阻止工具调用
