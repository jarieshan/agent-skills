# Todo Manager Skill

一个基于 Markdown 文件的轻量 todo 管理 skill，供 AI agent 通过 `/todo [指令]` 调用。支持想法收集、项目管理、任务汇总。

## 功能

- **查看** — 汇总展示任务状态，或查看特定项目进展
- **更新** — 添加任务/想法、标记完成、变更状态
- **整理** — 任务在 INBOX 和项目间移动、新建项目、归档建议

## 安装

将 `todo-manager/` 目录放到 `~/.claude/skills/` 下：

```
~/.claude/skills/todo-manager/
  SKILL.md
  config.json.template
  .gitignore
```

首次调用 `/todo` 时会交互式询问 todo 文件存储路径并完成初始化。

## 配置

- `config.json.template` — 配置模板，提交到 git
- `config.json` — 初始化后自动生成，包含真实路径，已被 `.gitignore` 排除

## Todo 目录结构

```
<todo_root>/
  INBOX.md          # 独立任务池 + 未成形的 idea
  PROJECTS.md       # 项目索引
  projects/
    <project>.md    # 每个项目一个文件
```

## 详细说明

完整的文件格式规范和操作行为定义见 [SKILL.md](SKILL.md)。
