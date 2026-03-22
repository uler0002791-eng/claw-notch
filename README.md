# Claw Notch

将 [OpenClaw](https://github.com/nicepkg/openclaw) AI 助手集成到 macOS 灵动岛（Dynamic Island）中。

> 本项目基于 [boring.notch](https://github.com/TheBoredTeam/boring.notch) 修改开发，感谢 TheBoredTeam 的开源项目。

## 功能特性

- **像素风小龙虾** — 收起和展开灵动岛中都有像素画龙虾，3 种状态（离线灰色 / 空闲彩色 / 工作中动画）
- **WebSocket 实时通信** — 连接 OpenClaw Gateway，实时监听 agent 事件（飞书、Discord 等外部消息自动触发龙虾动画）
- **消息同步 Dashboard** — 通过 WebSocket `chat.send` 发送消息，与 OpenClaw Dashboard 完全同步
- **展开灵动岛对话** — 左侧大像素龙虾状态图标，右侧聊天气泡界面（最近 5 条消息，支持快速输入）
- **消息历史持久化** — 重启应用后保留最近 50 条消息
- **标签页排序** — 可自定义灵动岛标签页顺序，将 OpenClaw 设为默认首页
- **一键打开 Dashboard** — 灵动岛内按钮直接拉起 OpenClaw Dashboard

## 截图

### 小龙虾三种状态（灵动岛收起时）

像素风小龙虾有 3 种状态：**离线**（灰色）、**空闲**（彩色静止）、**工作中**（彩色挥钳动画）。

![小龙虾状态](screenshots/lobster-states.png)

### 展开灵动岛

左侧：大像素龙虾显示当前活动状态。右侧：聊天气泡 + 快速输入框 + 打开 Dashboard 按钮。

![展开灵动岛](screenshots/expanded-notch.png)

## 环境要求

- macOS 14.0+
- [OpenClaw](https://github.com/nicepkg/openclaw) 本地部署运行

## 致谢

- [boring.notch](https://github.com/TheBoredTeam/boring.notch) — 本项目基于此开源项目修改开发
- [OpenClaw](https://github.com/nicepkg/openclaw) — AI 助手引擎
