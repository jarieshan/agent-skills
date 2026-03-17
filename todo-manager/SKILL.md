---
name: todo
description: "管理个人 todo 清单。查看任务、添加任务、标记完成、整理归档。支持想法收集、项目管理、任务汇总。当用户提到 todo、待办、任务、想法、项目进展时使用。"
argument-hint: "[指令，如：看看任务 / 加个任务xxx / 整理一下]"
---

# Todo Manager

## 初始化

首次调用时，检查 `~/.claude/skills/todo-manager/config.json` 是否存在。

**若不存在：**
1. 询问用户 todo 文件的存储路径（如 `~/todo`）
2. 基于 `config.json.template` 创建 `config.json`，填入用户指定的路径
3. 在该路径下创建初始结构：
   - `INBOX.md`（含 `# Ideas` 和 `# Tasks` 两个空 section）
   - `PROJECTS.md`（空文件）
   - `projects/` 目录

**若已存在：** 直接读取 `todo_root` 路径，跳过初始化。

**文件说明：**
- `config.json.template` — 提交到 git，记录配置结构，不含真实路径
- `config.json` — 本地生成，包含真实路径，通过 `.gitignore` 排除

## 目录结构

```
<todo_root>/
  INBOX.md          # 独立任务池 + 未成形的 idea
  PROJECTS.md       # 项目索引，列出项目名和对应文件路径
  projects/
    <project>.md    # 每个项目一个文件
```

## 文件格式

### 状态标记

`todo` / `doing` / `waiting` / `done`

### INBOX.md

```md
# Ideas

- 试试用 Rust 重写 CLI
- 做一个阅读进度追踪器
    - 可以参考 Goodreads 的模式

# Tasks

- [todo] 买新键盘
- [doing] 整理书架
    - 2026-03-15：已清理第一层
- [done] 交电费
```

Ideas 区域不需要状态标记，纯文本记录。当 idea 确定要做时，移到 Tasks 区域或归入某个项目。

### PROJECTS.md

```md
- [openclaw](projects/openclaw.md)
- [blog-redesign](projects/blog-redesign.md)
```

### 项目文件（projects/xxx.md）

```md
# Notes

项目级信息写在这里（可选）

# Tasks

- [doing] 设计 Todo 跟踪架构
    - 2026-03-11：确认采用"一个项目一个 md 文件"方案
- [todo] 实现 CLI 工具
- [done] 调研现有方案
```

### 格式规则

- 一级列表 `- [状态] 描述` 表示事项
- 子列表用于补充说明，格式自由
- 完成事项标记 `[done]`，保留在文件中不删除
- 项目文件用 `# Notes` 和 `# Tasks` 两个 section 组织

## 操作行为

用户通过 `/todo $ARGUMENTS` 调用，根据 `$ARGUMENTS` 的内容判断执行哪类操作。

### 查看

- "看看现在有什么任务" — 读取 INBOX 和各项目文件，汇总展示当前 doing/todo/waiting 状态的任务
- "openclaw 项目进展如何" — 读取对应项目文件，展示任务状态
- "汇总 todo" / "今日 todo" — 输出一份格式化的 todo 摘要（见下方「摘要格式」）

### 摘要格式

当用户要求汇总、摘要、总览时，按以下规则输出：

- 用中文输出
- 按项目分组，项目名加粗作为标题；INBOX 中的独立任务归入 **INBOX** 标题下
- 有截止时间的事项，时间放最前面用【】标注，如 `【2026.03.20】`
- **不展示 done 状态的事项**，只展示 doing / todo / waiting
- 正文保持简洁可扫读
- 长内容（SQL、长链接、详细备注）放到末尾「附录」区域，用 fenced code block 展示

**示例输出：**

````
**TODO 总览**

**INBOX**
- 买新键盘
- 【下周五】整理书架

**openclaw**
- 【2026.03.20】设计 Todo 跟踪架构
- 实现 CLI 工具

**附录**
- 某查询 SQL
```sql
select * from ...
```
````

**工作方式：**
- 每次增删改任务后，自动输出一份最新摘要
- 始终从 todo 文件读取，不依赖记忆作为权威来源
- 信息不确定时简要说明，不编造任务
- 保留用户原始措辞

### 更新

- "xxx 已经完成了" — 找到对应任务，标记 `[done]`
- "加个任务：调研 xxx" — 添加到 INBOX 的 Tasks，或用户指定的项目文件中
- "有个想法：做一个 xxx" — 添加到 INBOX 的 Ideas 区域
- "把 xxx 状态改成 waiting" — 更新对应任务状态

### 整理

- "把 INBOX 里的 xxx 移到 openclaw 项目" — 从 INBOX 移到对应项目文件
- "新建一个项目 blog-redesign" — 创建 `projects/blog-redesign.md`，更新 PROJECTS.md 索引
- "整理一下" — 读取全部文件，提出整理建议（如 idea 是否该转任务、任务是否该归入项目），逐条确认后执行

### 原则

- 所有写操作执行前，先告知用户将要做什么
- 找不到匹配任务时，列出候选让用户确认
- 不自动删除任何内容
