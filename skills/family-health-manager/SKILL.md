---
name: family-health
description: 管理家庭成员健康档案——归档新医疗资料、整理体检报告、查询用药与检查记录、追踪指标趋势、定位历史报告、为新成员建档。
---

# Family Health Data Manager

## Purpose

维护一套结构化、可追溯、可长期维护的家庭健康档案系统。

## 初始化

首次调用时，检查 `~/.claude/skills/family-health-manager/config.json` 是否存在。

**若不存在：**
1. 询问用户健康档案的存储路径（如本地挂载的 Google Drive 路径 `~/Google Drive/Family Health Data`，或其他本地路径）
2. 基于 `config.json.template` 创建 `config.json`，填入用户指定的路径

**若已存在：** 直接读取 `data_root` 路径，作为项目根目录。

**文件说明：**
- `config.json.template` — 提交到 git，记录配置结构，不含真实路径
- `config.json` — 本地生成，包含真实路径，通过 `.gitignore` 排除

## Trigger examples

- "帮我整理/归档这份体检报告"
- "把这个检查结果录入档案"
- "XX 现在在吃什么药"
- "最近的甲功结果怎么样"
- "这份报告放哪了"
- "帮 XX 建一份健康档案"

## Scope and default tools

本 skill 需要对 Google Drive 进行文件和表格操作，包括：

- 定位文件和文件夹
- 创建成员目录与事件目录
- 拉取、修改、上传 Markdown / Docs 内容
- 创建、读取、更新 Google Sheets tracker
- 移动、重命名、归档文件

请根据当前运行环境，自行选择最合适的可用方案来操作 Google Drive（如 MCP 工具、Google Drive API、本地挂载的 Google Drive 文件系统、gws、或其他可用工具）。

如果当前环境没有任何可用的 Google Drive 操作方案，请明确告知用户："当前环境无法访问 Google Drive，请确认是否已配置相关工具或挂载 Google Drive"，并列出可能的解决方案供用户参考。

不要删除源文件，除非用户明确要求。

## Operating principles

始终遵守以下原则：

1. **事实优先于总结**
   - 原始文件 > tracker 结构化记录 > `summary.md` > `profile.md`

2. **归档优先于解释**
   - 先把资料放到正确位置，再做结构化提取和总结

3. **更新优先于重复新增**
   - 能判断为既有事件、既有药物或既有检查记录时，优先更新而不是重复追加

4. **保守优先于猜测**
   - 遇到 OCR 不清、日期不明、成员不明、剂量模糊时，不把猜测写成事实

5. **回答尽量可追溯**
   - 回答时尽量附日期、`来源文件` 或 `归档路径`

## Privacy minimization

默认只保留归档、检索、追溯所必需的信息。
除非用户明确要求，不主动在回复、`summary.md` 或 tracker 中复述身份证号、手机号、住址、卡号等敏感标识。
优先使用日期、机构、文件名、相对路径来定位资料，而不是暴露额外个人信息。

## Gotchas

- 补充材料通常复用既有事件目录，不新增第二条 `timeline`
- 综合体检或综合报告不能作为该事件下所有 `measurements` 的统一 `来源文件`
- `summary.md` 不能覆盖原始文件事实；原始文件 > tracker > `summary.md` > `profile.md`
- 成员或日期不明时，不建正式事件目录，先入 `inbox/`
- 低置信度 OCR、药名/剂量/日期模糊时，不写正式结构化字段
- `measurements` 的 `检查细项` 命名规则见 `references/data-model.md` measurements 一节

## Load references when needed

按任务类型读取对应 reference：

- 需要确认目录结构、核心文件、tracker 表头和枚举时，读取 `references/data-model.md`
- 需要归档新资料、处理补充材料、判断是否重复、更新 tracker 时，读取 `references/ingestion-rules.md`
- 遇到综合体检、综合报告与单项报告并存、同机构近日期材料、或存在重复嫌疑时，额外读取 `references/deduplication-rules.md`
- 需要回答药物、检查、趋势、事件回溯、报告定位问题时，读取 `references/query-rules.md`
- 需要参考稳定做法与边界示例时，读取 `references/examples-ingestion.md`、`references/examples-deduplication.md` 与 `references/examples-query.md`

## Workflow router

Trigger: 用户要求整理、归档、更新资料，或上传新的医疗文件  
Instruction:
1. 读取 `references/data-model.md`
2. 读取 `references/ingestion-rules.md`
3. 如存在综合体检、单项报告并存、日期接近或重复嫌疑，追加读取 `references/deduplication-rules.md`
4. 在写入前读取现有档案（至少 `profile.md`、`timeline`、相关 `records/`，必要时读取 `medications` / `measurements`）
5. 仅在高置信度下写入结构化字段
6. 完成后按“Completion contract”汇报

Trigger: 用户要求查询、总结、定位资料  
Instruction:
1. 读取 `references/query-rules.md`
2. 识别问题类型（药物 / 检查 / 趋势 / 事件 / 报告定位 / 长期背景）
3. 先读取最相关的数据源，必要时补读 `summary.md` 或原始文件
4. 先回答结论，再给证据，再说不确定性

Trigger: 资料存在 OCR 不清、成员不明、日期不明或重复嫌疑
Instruction:
1. 采用保守处理
2. 不强行写入正式结构化字段
3. 把低置信度信息放入 `待确认事项`、`备注` 或 `inbox/` 待确认区域

Trigger: 用户要求为新成员创建健康档案
Instruction:
1. 确认成员基本信息（姓名、别名、出生日期等）
2. 创建成员目录及 `records/` 子目录
3. 创建 `profile.md`（含 YAML front matter），结构见 `references/data-model.md`
4. 创建 `健康数据追踪` Google Sheet，含 `medications` / `measurements` / `timeline` 三个 tabs
5. 按 `references/data-model.md` 规范初始化表头

## Write checklist

在任何写入任务中，按此顺序执行并自检：
1. 读取现有档案
2. 判断是新事件、补充材料还是重复材料
3. 决定目标成员、事件目录与文件名
4. 更新 `summary.md`
5. 仅在高置信度下更新 tracker 与 `profile.md`
6. 结束前逐项核对：
   - 是否误建重复事件
   - 是否误增重复 tracker 行
   - 是否用不确定信息覆盖了已确认事实
   - `来源文件` 是否指向最直接的单项原始文件

## Safety rules

不要：
- 在 `data_root` 配置的目录外操作，除非用户明确改范围
- 删除原始资料
- 用不确定信息覆盖已确认事实
- 把档案整理扩展成医学诊断结论
- 在低置信度情况下自动合并重复记录

## Error handling

当流程中出现以下情况时，立即停止当前操作并告知用户检查：
- 工具调用报错或权限不足
- 目标文件或目录无法读取、写入或创建
- 数据冲突且无法自动判断正确性
- 写入后校验发现内容与预期不一致

不要在错误后继续猜测性执行后续步骤。

## Expected outcome

一次成功执行后，应满足：

- 文件归档到正确成员和事件目录
- `summary.md` 清晰说明事件和文件
- tracker 更新干净、不重复、可追溯
- `profile.md` 仅在长期高价值变化时更新
- 回答健康问题时，能指出主要来源

## Completion contract

归档或更新任务完成后，回答中必须使用以下结构：

```md
## 执行结果
- 目标成员：
- 事件目录：复用 / 新建
- 文件变更：
- 更新的 tracker：
- `profile.md`：已更新 / 未更新（原因）
- 待确认事项：
- 关键来源：
```

查询任务完成后，回答中必须：
- 先给结论
- 证据在正文中使用论文引用式编号，例如 `[1]`、`[2]`
- 在最后单独列出 `引用来源`，逐条给出日期、`来源文件`、`归档路径` 或事件目录
- 最后说明冲突或不确定性
