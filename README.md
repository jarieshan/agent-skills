# Agent Skills

自建的 Claude Code skill 集合，用于扩展 AI agent 的能力。

## Skills 列表

| Skill | 调用方式 | 说明 |
|-------|---------|------|
| [todo-manager](todo-manager/) | `/todo [指令]` | 基于 Markdown 的轻量 todo 管理，支持想法收集、项目管理、任务汇总 |

## 安装

运行交互式安装脚本，按提示选择 skill 和安装路径：

```bash
./install.sh
```

脚本支持键盘交互：↑↓ 移动、Space 切换选中、Enter 确认、a 全选/全不选。

也可以通过参数非交互式安装：

```bash
# 安装指定 skill 到默认路径 (~/.claude/skills/)
./install.sh --skill todo-manager

# 指定安装路径
./install.sh --skill todo-manager --path ~/my-skills

# 查看可用 skills
./install.sh --list
```

Skills 通过 symlink 安装，`git pull` 即可更新。

## Skill 结构

每个 skill 目录至少包含：

```
<skill-name>/
  SKILL.md              # skill 定义文件，Claude Code 据此执行
  README.MD             # 说明文档
```

## 许可

个人使用。
