# Codex 兼容方案

本方案回应「能否直接放到 Codex 使用」的诉求：在同一个仓库中同时保留 Claude Code / OpenClaw 的既有结构，并按 Codex 官方 marketplace/plugin 形态提供接入入口。

## 调研结论

复核 OpenAI 官方 Codex plugin 文档后的结论：Codex 更推荐通过 **marketplace → plugin folder → `.codex-plugin/plugin.json` → `skills/`** 的层级接入，而不是让用户手动复制 skill 目录。

官方文档中的关键点：

1. plugin 作者应创建带 `.codex-plugin/plugin.json` 的插件目录，并在 manifest 中声明 `skills: "./skills/"`。
2. repo/team 级 marketplace 放在 `$REPO_ROOT/.agents/plugins/marketplace.json`。
3. marketplace 的每个 `plugins[]` 条目应让 `source.path` 指向插件目录，并使用以 `./` 开头、相对 marketplace root 的路径。
4. CLI 安装 marketplace 使用 `codex plugin marketplace add owner/repo`；本地目录可用 `codex plugin marketplace add ./local-marketplace-root`。
5. 当前 Codex 对 marketplace `source.path: "./"` 指向仓库根的支持并不稳妥，因此本仓库不把 plugin 放在 repo root，而是放入 `plugins/oh-story-claudecode/`。

## 设计目标

1. **使用官方 plugin 形态**：提供 `.agents/plugins/marketplace.json` 和 `plugins/oh-story-claudecode/.codex-plugin/plugin.json`。
2. **不改动原 skill 内容**：`skills/*/SKILL.md` 与引用资料保持原样，避免为了 Codex 适配而改写技能正文。
3. **单一技能来源**：Codex plugin 通过 `plugins/oh-story-claudecode/skills -> ../../skills` 指向仓库根 `skills/`，避免复制两份 skill 内容。
4. **双入口并存**：Claude Code / OpenClaw 继续读取 `.claude-plugin/marketplace.json`；Codex 读取 `.agents/plugins/marketplace.json` 和插件 manifest。
5. **可验证**：`scripts/smoke-test-codex-compat.sh` 会验证 marketplace、plugin manifest、skill 发现和每个 skill 的 Codex 元数据。

## 当前仓库结构

```text
.claude-plugin/marketplace.json                 # Claude Code / OpenClaw 入口，保留不变
.agents/plugins/marketplace.json                # Codex repo marketplace
plugins/oh-story-claudecode/.codex-plugin/      # Codex plugin manifest
plugins/oh-story-claudecode/skills -> ../../skills
skills/                                         # 单一 skill 正文来源
skills/*/agents/openai.yaml                     # Codex skill 展示/发现元数据
scripts/smoke-test-codex-compat.sh              # Codex plugin 兼容性烟测
```

## 使用方式

### 从 GitHub 安装 marketplace

```bash
codex plugin marketplace add worldwonderer/oh-story-claudecode
```

然后重启 Codex，打开 `/plugins`，选择 Oh Story Plugins marketplace，安装并启用 Oh Story。

### 本地调试 marketplace

在仓库根目录执行：

```bash
codex plugin marketplace add .
```

然后重启 Codex，打开 `/plugins`，从本地 marketplace 中安装并启用 Oh Story。

## 与已迁移 Codex 版本的取舍

对 issue 23 和迁移版仓库的复核结论是：Codex 需要 official plugin/marketplace 入口以及每个 skill 的 `agents/openai.yaml` 展示/发现元数据。迁移版还将部分 `SKILL.md` frontmatter、路由语法和项目初始化流程改为 Codex 风格，但这会触碰原 skill 内容或产生双份维护成本。

本仓库采用更保守的兼容层策略：

- **采纳**：增加 Codex marketplace、plugin manifest，并为每个 skill 增加 `agents/openai.yaml` 展示/发现元数据。
- **暂不采纳**：批量改写 `SKILL.md` frontmatter、改写 `story-setup` 的 Claude 项目初始化正文、整体替换 Claude 风格 agent/project setup 流程。
- **原因**：当前目标是「同仓双端兼容」和「不修改原本 skill 内容」，不是建立独立 Codex fork。

## 验证

运行以下命令检查 Codex 入口和 skills 发现条件：

```bash
bash scripts/smoke-test-codex-compat.sh
```

该检查会验证：

- `.agents/plugins/marketplace.json` 是合法 JSON，且指向 `./plugins/oh-story-claudecode`。
- `plugins/oh-story-claudecode/.codex-plugin/plugin.json` 是合法 JSON，且 `skills` 为 `./skills/`。
- plugin 路径下能发现每个预期 skill 的 `SKILL.md`。
- 每个 `SKILL.md` 至少包含 Codex/Claude 都需要的 `name` 和 `description` frontmatter。
- 每个预期 skill 目录都有 `agents/openai.yaml`，且包含 Codex UI 需要的 `interface.display_name`、`short_description` 和 `default_prompt`。

## 已知边界

- `plugins/oh-story-claudecode/skills` 使用符号链接指向根 `skills/`，以满足官方插件目录形态并避免维护两份 skill 内容。若未来要发布不依赖 symlink 的归档包，可在发布流程中物化复制该目录。
- `story-setup` 的正文仍以 Claude Code 项目初始化为主，会生成 `.claude/`、`CLAUDE.md` 和 Claude hooks。为了遵守「不改动原 skill 内容」，本次不把它改写为 Codex 项目初始化器。
- Codex 多代理委派语义与 Claude subagent 注册不同；现有审查/探索类说明可作为方法论参考，但不在本次最小兼容层中强行转换。
- `agents/openai.yaml` 只解决 Codex 侧 skill 展示/发现问题，不等同于把 `story-setup` 部署出的 Claude subagent 模板转换为 Codex 原生 agent。
- 如果后续要提供完整 Codex lifecycle hooks，应优先新增独立 `hooks/` 适配层，并在文档中标注其与 Claude hooks 的行为差异。
