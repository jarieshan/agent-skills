# Agent Skills

自建的 Claude Code skill 集合，用于扩展 AI agent 的能力。

## Skills 列表

| Skill | 调用方式 | 说明 |
|-------|---------|------|
| [todo-manager](todo-manager/) | `/todo [指令]` | 基于 Markdown 的轻量 todo 管理，支持想法收集、项目管理、任务汇总 |

## 安装

### 一键安装（推荐）

无需手动 clone，直接运行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/jarieshan/agent-skills/main/setup.sh)
```

脚本会自动 clone 仓库到 `~/.config/agent-skills/repo/`，然后启动交互式安装。
已安装过的用户再次运行会优先提供 Update 选项。

### 手动安装

```bash
git clone https://github.com/jarieshan/agent-skills.git
cd agent-skills
./setup.sh
```

### 子命令

```bash
./setup.sh                    # 交互式（已安装则选 Update/Install）
./setup.sh install             # 安装 skills
./setup.sh update              # 更新已安装的 skills
./setup.sh status              # 查看已安装状态
./setup.sh list                # 列出可用 skills
./setup.sh clean-backup        # 管理备份
./setup.sh help                # 查看帮助
```

### Install 选项

```bash
./setup.sh install --target cursor      # 安装到 Cursor
./setup.sh install --skill todo-manager # 非交互式安装指定 skill
./setup.sh install --path ~/my-skills   # 自定义路径
./setup.sh install --method symlink     # 软链接模式
```

### Update 选项

```bash
./setup.sh update                       # 更新所有
./setup.sh update --target claude       # 只更新 Claude Code 的 skills
```

### 远程使用

```bash
bash <(curl -fsSL .../setup.sh) update
bash <(curl -fsSL .../setup.sh) install --skill todo-manager
bash <(curl -fsSL .../setup.sh) status
```

## Skill 结构

每个 skill 目录至少包含：

```
<skill-name>/
  SKILL.md              # skill 定义文件，Claude Code 据此执行
  README.MD             # 说明文档
```

## 许可

个人使用。
