# Project Flight Control

## Codex 三角色项目闭环控制 Skill 产品与行为设计规格

- **文档版本**：`PFC-DESIGN-v1.0-approved`
- **日期**：2026-09-03
- **状态**：`APPROVED_FOR_IMPLEMENTATION`
- **本轮收敛决策**：`D-032` 至 `D-069`
- **目标平台**：Codex
- **V1 正式支持环境**：Windows 10/11、PowerShell、Git for Windows、Codex 本地环境
- **实现状态**：`NOT_RUN`
- **行为评估状态**：`NOT_RUN`
- **Specialist 运行时能力状态**：`UNKNOWN`
- **Specialist 是否为核心发布依赖**：`NO`
- **仓库名称**：`codex-project-flight-control`
- **Skill 名称**：`project-flight-control`
- **显式调用**：`$project-flight-control`
- **显示名称**：`Project Flight Control`
- **中文名称**：`Codex 项目航向控制`

> 本文档已于 2026-09-03 获用户整体批准，是多轮设计决策的唯一权威规格。D-032 至 D-069 已直接并入对应章节，不另建效率扩展或 Specialist 扩展规格。它用于交付 Codex 实现 Skill、两个正式 Custom Agent、Windows 安装工具和行为评估，不是最终 `SKILL.md`，也不代表实现、Token 降低、Specialist 可用性或发布门禁已经通过验证。

---

# 1. 产品定义

## 1.1 一句话定义

Project Flight Control 是一个只允许显式调用的 Codex Skill，用于高难度、长周期、跨里程碑的软件开发任务。它通过 Goalkeeper、Builder、Verifier 三个隔离角色维护目标、范围、版本、证据、返工和最终验收闭环；仅 Builder 使用专属执行效率协议，额外专业判断通过受控、临时、窄范围的 Specialist Subagent 获得。

## 1.2 要解决的问题

长期使用 Codex 开发时，项目容易出现以下问题：

- 开发过程中最初目标逐渐模糊；
- 不知道当前实现是否已偏离目标；
- Builder 自述完成，但缺少独立证据；
- 实现、审查、最终完成判断由同一上下文承担；
- 对话变长后，调试噪声淹没目标和决策；
- 中断或更换会话后，无法可靠恢复项目状态；
- 不知道当前做到哪里、剩余什么、还需多少有效工作；
- 修复后没有绑定准确版本重新验证；
- 多轮返工不收敛却仍持续消耗时间和额度；
- Builder 重复读取未变化代码、重复搜索、重复实现已有能力；
- Builder 对同一失败进行猜测性修补，或机械重复全部测试与构建；
- 为了增加角色和工具而加载过多协议，反而扩大上下文和 Token 成本。

## 1.3 核心原则

```text
Builder 产出候选实现。
Verifier 证明候选实现是否可靠。
Goalkeeper 判断可靠实现是否真正完成批准目标。
```

必须始终满足：

```text
实现者 != 独立验证者 != 最终验收者
```

同时遵守：

```text
一个事实源，三个独立且最小化的正式角色上下文。
执行效率优化属于 Builder；上下文边界属于控制协议。
正确性、安全性和证据完整性高于 Token 优化。
未变化且已被可靠证明的工作，不应无理由重新推演。
```

Specialist 不是第四个正式角色，只是由 Goalkeeper 按问题批准的一次性专业咨询线程。

## 1.4 V1 目标

V1 必须做到：

1. 用户显式调用后，当前主线程成为 Goalkeeper；
2. 按阶段创建真实、独立的 Builder 与 Verifier Subagent Thread；
3. 使用 Git Commit、Worktree、Candidate SHA 和证据链冻结验证对象；
4. 每个里程碑形成实施、验证、返工、复验、验收闭环；
5. 项目事实写入仓库，而不是只存在于聊天记录；
6. 中断后可以从 Git、控制文件和证据恢复；
7. 目标、范围、证据或预测出现异常时暂停，而不是继续扩展实现；
8. 所有必需里程碑通过后执行全新的 Goal 级最终审计；
9. Windows 上提供安全安装、升级、卸载和诊断能力；
10. 通过分层 RED–GREEN 行为评估证明 Skill 实际改变了 Codex 行为；
11. Builder 启动时自动获得精简的执行效率纪律，并按证据从窄到宽获取上下文；
12. Builder 优先复用已有能力、产生最小 Diff、执行增量验证并限制猜测性修复；
13. Verifier 从最小验证包开始，复用有效证据但执行必要的独立复验；
14. 在运行时能力经真实验证可用时，必要专业判断通过临时 Specialist 完成，不增加固定正式角色；
15. 验证默认保存紧凑证据，失败或高风险场景才保留受限、脱敏附件；
16. 通过 Builder 协议对照与完整三角色流程对照，分别评估重复工作和总体交付价值；
17. 将 Runtime Specialist 作为受能力门禁控制的条件增强：它不可用时不阻断三角色核心发布，但必须诚实报告状态，并在任务确实依赖它时安全阻塞。

## 1.5 V1 非目标

V1 不负责：

- 普通、低风险、一次性小修改的快速执行；
- 自动推送远程仓库；
- 自动创建或合并 Pull Request；
- 自动合并到 `main`、`master` 或其他正式分支；
- 自动发布、部署或变更生产环境；
- 自动处理用户原工作区未提交修改；
- 非 Git 项目的完整实施与正式验收；
- macOS、Linux 的正式兼容承诺；
- 其他智能体平台的适配；
- Company OS 集成、项目组合管理、市场分析或公司级状态管理；
- FAST / STANDARD / DEEP 或 SIMPLE / COMPLEX 等任务复杂度路由系统；
- 安装固定 Architect、Debugger、Security、Database、Performance 等额外角色；
- 保证所有 Codex 客户端都支持无固定 TOML 的 Runtime Specialist；未经有效主动验证不得声明 `AVAILABLE`；
- 安装 Serena、Atlas、GitNexus、Beads 或其他外部效率基础设施；
- 构建 Repo Map、语义索引、Embedding、文件读取数据库、长期 Agent Memory 或内容 Hash 缓存；
- 正式运行时的 Token 数据库、文件访问监控、后台遥测或长期行为追踪；
- 承诺固定 Token 节省比例、成本降低比例或速度提升倍数；
- 用仪表盘替代仓库内的唯一状态事实源。

---

# 2. 已确认设计决策登记

| ID | 设计项 | 已确认方案 |
|---|---|---|
| D-001 | Skill 触发方式 | 只允许显式调用 |
| D-002 | Subagent 创建时机 | 按阶段创建、按里程碑归档 |
| D-003 | 运行模式识别 | 用户可指定；未指定时 Goalkeeper 自动识别 START / RESUME / AUDIT / STATUS_ONLY |
| D-004 | 角色隔离 | 调用 Skill 后强制执行，不允许降级为主线程自演三角色 |
| D-005 | 里程碑后推进 | 默认停止；允许用户预先开启受控连续模式 |
| D-006 | 项目控制文件 | 优先复用现有文件，只补充缺失职责 |
| D-007 | 控制文件写入者 | Goalkeeper 单一写入 |
| D-008 | Subagent 回执 | 结构化回传，由 Goalkeeper 校验并统一持久化 |
| D-009 | Git 前提 | 实施与正式验收强制要求 Git |
| D-010 | 本地提交 | 允许受限本地提交；远程、合并、发布另行授权 |
| D-011 | Verifier 工作区 | 独立验证 Worktree + 受限可写权限 |
| D-012 | Goalkeeper/Builder 工作区 | 分时使用专用里程碑 Worktree |
| D-013 | 基线 | 只使用可确认的已提交基线，不自动处理原工作区改动 |
| D-014 | 角色配置 | Skill + 两个正式 Codex Custom Agent 配置 |
| D-015 | 安装作用域 | 个人级全局安装 |
| D-016 | 模型策略 | 继承主线程模型；按角色、任务清晰度和风险指定推理强度，不固定所有线程为 high |
| D-017 | 自动返工 | 默认允许两次自动返工，并执行收敛检查 |
| D-018 | Finding 等级 | `BLOCKER / MAJOR / MINOR`，绑定客观证据 |
| D-019 | 审查约束力 | 有效阻断结论不可被 Goalkeeper 直接推翻 |
| D-020 | 合同变更 | 分级变更权限 |
| D-021 | 中断恢复 | 从持久化状态恢复，并创建新 Subagent |
| D-022 | Worktree 清理 | 分级清理 |
| D-023 | 里程碑继承 | 下一里程碑继承上一 Accepted Checkpoint SHA |
| D-024 | Goal 完成 | 强制全新的 Goal 级最终审计 |
| D-025 | 本地/人工验证 | 结构化人机协作验证 |
| D-026 | 版本模型 | Candidate SHA + Accepted Checkpoint SHA |
| D-027 | 首版平台 | Windows 优先，核心协议平台中立 |
| D-028 | 名称 | Project Flight Control |
| D-029 | 文件组织 | 分层模块化、渐进式加载 |
| D-030 | 安装机制 | 安全事务式安装 + 清单 + 备份 |
| D-031 | 行为评估 | 分层 RED–GREEN 行为评估 |
| D-032 | Builder 效率协议启用 | 每个 Builder 启动时强制加载核心纪律，具体动作按证据触发 |
| D-033 | 额外专业角色 | 支持通用临时 Specialist，不增加固定正式角色 |
| D-034 | Specialist 结论效力 | 只提供专业证据和建议，不直接发布正式阻断或验收状态 |
| D-035 | Specialist 上下文 | 窄范围 Context Packet + 固定 SHA 的只读访问 |
| D-036 | Specialist 生命周期 | 按问题串行；最多一次证据补充；完成后立即结束 |
| D-037 | Builder 上下文复用 | 复用当前 Builder Thread、Git/SHA 和差量，不建立持久化读取缓存 |
| D-038 | Verifier 上下文 | 从最小验证包开始，按风险逐级扩展 |
| D-039 | Goalkeeper 代码读取 | 允许一次受限、只读的合同级侦察，不下沉为实现分析 |
| D-040 | 侦察结果持久化 | 只压缩进 Milestone Contract，不创建 Discovery Report |
| D-041 | Execution Contract | 作为 Milestone Contract 的运行语义，不新增独立合同文件 |
| D-042 | Builder 协议组织 | 高频规则固化在 Builder TOML，低频调试和 Specialist 协议按需加载 |
| D-043 | 效率规则约束 | 强制遵守，正常路径不汇报；只有扩大最小路径时报告例外 |
| D-044 | 效率例外审查 | Goalkeeper 审查过程例外；Verifier 只检查可观察交付结果 |
| D-045 | 效率偏离与验收 | 过程偏离不自动阻断；只有形成可观察交付缺陷或合同变化时阻断 |
| D-046 | 上下文与搜索额度 | 不设固定文件数、搜索数或 Token 上限；按三层证据逐级扩展 |
| D-047 | 增量验证责任 | 合同定义必须证明什么；Builder 选择最小命令；Verifier 判断证据充分性 |
| D-048 | 验证证据复用 | Verifier 复用有效证据，同时执行最小独立复验并按风险扩大 |
| D-049 | 验证输出保存 | 紧凑 Evidence Record 为默认；必要时保存受限、脱敏附件 |
| D-050 | 失败诊断责任 | 当前 Builder 按需加载调试协议；专业缺口才申请 Specialist |
| D-051 | Builder 内部修复上限 | 同一失败路径最多两次证据驱动的代码修复尝试 |
| D-052 | 跨 Revision 收敛 | 内部修复与正式返工上限独立，并增加 Goalkeeper 跨 Revision 门禁 |
| D-053 | 收敛状态持久化 | 最新快照写入现有 STATUS 与报告，不新增日志文件 |
| D-054 | 效率效果验证 | 双层离线 RED–GREEN 对照；正式运行时不增加 Token 计量基础设施 |
| D-055 | 效率评估标准 | 统一质量底线 + 场景级效率目标；不设置全局 Token 节省百分比 |
| D-056 | 效率发布门禁 | 质量与核心效率行为必须通过；量化 Token 指标先作为证据 |
| D-057 | Specialist 安装方式 | 运行时创建通用临时 Subagent，不安装固定 Specialist TOML |
| D-058 | Specialist Worktree | 每次使用独立、固定 SHA、可丢弃 Worktree |
| D-059 | Specialist 命令权限 | 默认静态检查；必要时执行与问题绑定的最小诊断命令 |
| D-060 | Specialist 消息 | `SPECIALIST_REQUEST / ORDER / REPORT`；只持久化已批准任务和最终结果 |
| D-061 | Specialist 调用期间 | 作为同步决策门禁，暂停受其结论影响的工作 |
| D-062 | Specialist Report 适用性 | 证据严格绑定旧 SHA；建议经适用性检查后可复用 |
| D-063 | Specialist 未解决 | 根据是否属于当前合同的验收必要前提分级处理 |
| D-064 | 用户风险权限 | 不能把证据缺口豁免为 PASS；可正式变更合同、拆分里程碑或接受非阻断风险 |
| D-065 | 合同变化与风险持久化 | 复用 Milestone Contract 与 DECISION，不新增风险或豁免文件 |
| D-066 | 主规格合并 | 直接修订、去重并收敛现有主规格，保持一个权威设计文档 |
| D-067 | Specialist 与 V1 发布边界 | Specialist 是条件增强，不阻断三角色核心 V1 发布；必要任务仍按能力门禁处理 |
| D-068 | Specialist 能力检测时机 | `doctor` 做预检，实际调用前再做轻量复核 |
| D-069 | Specialist 能力主动验证 | 普通 `doctor` 被动且零模型调用；显式 Smoke Test 或一次真实成功调用才能确认 `AVAILABLE` |

---

# 3. 运行拓扑

## 3.1 固定正式角色拓扑

```text
用户
  │
  ▼
Goalkeeper 主线程
  ├─ Builder Subagent Thread
  └─ Verifier Subagent Thread
```

V1 的正式权责角色始终只有三个：

```text
Goalkeeper
Builder
Verifier
```

中心式编排：

```text
Goalkeeper → Builder → Goalkeeper → Verifier → Goalkeeper
                           ▲                        │
                           └──── REWORK_ORDER ─────┘
```

Builder 与 Verifier 不得直接向对方下达正式指令。

## 3.2 临时 Specialist 扩展

当安全、数据库、并发、性能、协议等窄问题会实质改变实现或验收判断，Goalkeeper 可以按问题创建一次性 Specialist：

```text
Goalkeeper
   └─ Specialist Subagent Thread（可选、临时、非正式角色）
```

Specialist：

- 不属于固定团队；
- 不安装独立 Agent TOML；
- 不进入常规任务路径；
- 不承担实现、正式验证或最终验收；
- 完成一个结构化专业结论后立即结束。

它的存在不改变三角色责任链，也不是三角色核心 V1 的发布硬依赖。运行时能力未经有效主动验证时不得高于 `UNKNOWN`；前置条件明确缺失时为 `UNAVAILABLE`。

## 3.3 线程生命周期

### Goalkeeper

- 生命周期：整个项目 Goal 或主要版本；
- 负责保持低噪声控制上下文；
- 项目恢复不依赖旧主线程仍然存在。

### Builder

- 当前里程碑进入 `ACTIVE` 后创建；
- 同一里程碑内可以处理 R1、R2、R3；
- 同一里程碑优先复用当前 Builder Thread；
- Builder Thread 丢失时从结构化事实恢复，不回放旧聊天全文；
- 里程碑结束后逻辑关闭；
- 下一里程碑必须创建新 Builder Thread。

### Verifier

- Candidate SHA 冻结后创建；
- 同一里程碑内可以复验后续 Revision；
- 发生独立复验时必须新建 Verifier Thread；
- Goal 最终审计必须新建 Verifier Thread；
- 里程碑结束后逻辑关闭。

### Specialist

- 只有 Goalkeeper 批准 `SPECIALIST_REQUEST` 后才创建；
- 一个 Thread 只处理一个明确专业问题；
- 同一时刻最多一个活动 Specialist；
- 最多允许一次受控证据补充；
- 使用固定 SHA 的独立可丢弃 Worktree；
- 返回最终 `SPECIALIST_REPORT` 后立即结束；
- 中断恢复时可在同一个 `SPECIALIST_ORDER` 下创建替代线程，不视为第二次专业咨询。

## 3.4 禁止的降级与膨胀行为

启用 Skill 后，禁止：

- Goalkeeper 在主线程中模拟 Builder；
- Goalkeeper 在主线程中模拟 Verifier；
- 使用一个通用 Agent 同时完成实现与验收；
- Builder 自审后直接宣布完成；
- 缺少 Verifier 配置时继续实施；
- 因任务“看起来简单”而跳过隔离流程；
- 把 Specialist 变成常驻第四角色；
- 为同一问题自动创建多个 Specialist 争论；
- Specialist 创建下级 Subagent；
- 引入 FAST / STANDARD / DEEP 等额外任务模式。

简单任务应通过“不调用本 Skill”处理，而不是在 Skill 内降级。角色固定，单次工作量可根据合同自然缩放。

---

# 4. 角色职责、权限与上下文边界

## 4.1 Goalkeeper

### 职责

- 识别或采用用户指定的运行模式；
- 只读建立 Git 与项目事实基线；
- 为形成可靠合同执行一次受限、只读的合同级侦察；
- 维护 Goal、Milestone、范围、非范围、约束与验收标准；
- 指定项目事实的唯一权威来源；
- 将 Milestone Contract 投影为最小 `WORK_ORDER` 与 `VERIFY_ORDER`；
- 创建并调度 Builder、Verifier；
- 审查 Builder 报告的 `EFFICIENCY_EXCEPTION`；
- 批准、拒绝和管理临时 Specialist；
- 管理里程碑 Worktree 的写入租约；
- 校验 Subagent 报告字段、Epoch、Revision 和 SHA；
- 持久化结构化回执、紧凑证据和必要附件；
- 维护最新 `CONVERGENCE_SNAPSHOT`；
- 根据证据作出 `REPAIR / BLOCKED / CHANGED / ACCEPTED` 决定；
- 更新状态、路线、决策和预测；
- 执行中断恢复；
- 输出 Project Pulse 与最终控制回执。

### 合同级侦察边界

Goalkeeper 可以按需读取：

```text
权威项目控制文件与最近层级 AGENTS.md
Git HEAD、状态、基线和已提交变化
项目清单、架构说明、测试与构建入口
用户明确指定的模块或文件
形成范围、风险和验收标准所必需的少量实现与相邻测试
```

Goalkeeper 不得：

```text
扫描整个仓库来设计具体实现
完整追踪调用链或调试实现问题
为 Builder 制定逐文件、逐函数修改方案
因“可能相关”而持续扩大读取范围
建立独立 Discovery Report
```

侦察结论只压缩为 Milestone Contract 中的 `Baseline Observations`、`Evidence References` 和 `Unverified Assumptions`。

### 权限

可以：

- 读写权威项目控制文件；
- 创建控制记录 Commit；
- 创建、登记和安全移除 Worktree；
- 创建本地里程碑分支；
- 向 Builder、Verifier 下达正式任务；
- 创建和关闭获批的临时 Specialist；
- 暂停或关闭 Subagent Thread。

不可以：

- 修改业务源代码；
- 修改测试实现；
- 代替 Builder 实现或调试；
- 代替 Verifier 独立验证；
- 在主线程模拟 Specialist；
- 直接推翻有效 `BLOCKER / MAJOR`；
- 把未证明事实通过风险接受改写为 PASS；
- 未经批准修改实质合同；
- 自动 Push、Merge、Rebase、发布或部署。

## 4.2 Builder

### 职责

- 只根据当前 `WORK_ORDER` 实施；
- 从 `WORK_ORDER`、项目约束和 Base SHA 开始；
- 修改授权范围内的业务代码和测试；
- 自动遵守 Builder 核心执行效率协议；
- 执行自测与增量验证；
- 失败时按需加载 `builder-debugging.md` 并进行根因诊断；
- 遇到窄范围专业缺口时提交 `SPECIALIST_REQUEST`；
- 创建本地 Candidate Commit；
- 返回结构化 `BUILD_REPORT`；
- 根据正式 `REWORK_ORDER` 做差量修复；
- 准确报告 `PASS / FAIL / PARTIAL / NOT_RUN`。

### 核心执行效率协议

每个 Builder Thread 启动时强制生效：

```text
1. Start From Evidence
   从 WORK_ORDER、Base SHA、Git 状态和最近层级项目规则开始。

2. Targeted Context
   先读目标实现、相邻实现和相邻测试，再按证据扩大范围。

3. Reuse Before Create
   新建公共组件、函数、服务、工具、脚本、依赖或配置机制前，
   在存在重复概率时定向检查现有能力、项目模式和已安装依赖。

4. Minimal Diff
   只修改完成当前合同所必需的内容，不顺手重构、统一无关格式、
   清理旧代码或增加未来可能需要的抽象。

5. Incremental Verification
   从最小复现或目标测试开始，按风险扩大到模块、Lint、类型检查、
   构建和更广回归验证。

6. Delta Rework
   返工只处理未通过 Finding 及受其影响的回归，不重新实施已通过且未变化的内容。

7. Accurate Reporting
   只根据实际命令、退出码和证据报告状态。
```

### 三层上下文扩展

```text
第 1 层：直接证据
- WORK_ORDER
- 最近层级 AGENTS.md
- Base SHA / Git 状态
- 明确目标文件
- 目标实现与相邻测试

第 2 层：局部关联
- 同模块现有模式
- 精确符号与引用
- 直接调用方 / 被调用方
- 相关类型与配置

第 3 层：扩大调查
- 跨模块调用链
- 全局同类能力搜索
- 更广兼容性分析
- 更大验证范围
```

第 1 层不足才进入第 2 层；第 2 层确认跨模块影响才进入第 3 层。V1 不设置固定文件数、搜索数、模块数或 Token 上限。

### 效率例外

Builder 正常执行时不提交固定效率清单。只有偏离最小路径时，才在 `BUILD_REPORT` 中增加：

```text
EFFICIENCY_EXCEPTION
Trigger:
Action:
Reason:
Affected Scope:
```

典型触发包括：跨目标模块扩大搜索、新增依赖、新建可能已有等价能力的公共抽象、修改未预期文件、运行完整测试套件、重读已通过且未变化的实现、返工时重做无关内容。

`EFFICIENCY_EXCEPTION` 只是必要性说明，不自动构成违规或阻断。Goalkeeper 审查过程例外；Verifier 只检查真实 Diff 与交付结果。

### 不可以

- 修改 Goal、Roadmap、Status、Decision 和 Evidence 索引；
- 自行扩大合同范围；
- 静默改变验收标准；
- 无依据先扫描整个仓库；
- 将无关未提交改动纳入 Candidate；
- 通过删除测试、降低断言或减少必要验证制造 PASS；
- 宣布 `ACCEPTED` 或 `GOAL_ACCEPTED`；
- 直接命令 Verifier 或自行创建 Specialist；
- Push、Merge、Rebase、Reset、删除分支或发布。

## 4.3 Verifier

### 职责

先后执行：

1. `Alignment Audit`：做的事情是否仍然正确；
2. `Evidence Integrity Check`：候选版本和证据是否匹配；
3. `Technical Verification`：正确的事情是否被正确实现。

Verifier 从最小验证包开始：

```text
Milestone Contract / VERIFY_ORDER
Base SHA 与 Candidate SHA
真实 Diff 与 Changed Files
Builder 的紧凑验证证据
受影响实现和相邻测试
相关 Specialist Report（如有）
```

Verifier 不接收 Builder 的完整聊天、内部推理、无关失败历史或整仓库历史。

需要检查：

- 需求完整性；
- 逻辑正确性；
- 边界情况；
- 代码质量；
- 测试覆盖；
- 实际运行结果；
- Git 版本完整性；
- 越界修改；
- 重复实现、无必要依赖或过度抽象等可观察问题；
- 本地、浏览器、设备或人工验证缺口。

Verifier 可以复用绑定当前 Candidate SHA 的有效证据，但不能继承 Builder 的结论。至少独立执行：

```text
Candidate 版本完整性检查
核心变更的目标测试或运行检查
此前失败、当前声称已修复的验证
从 Diff 识别出的高风险边界
```

证据缺失、Candidate 变化、高风险变更、影响范围被低估、项目规则要求或 Specialist 指出额外风险时，必须扩大验证。

Verifier 不审计 Builder 的搜索次数、文件读取数量或“是否足够省 Token”；但真实 Diff 中的越界修改、重复实现、不必要依赖、过度抽象或验证不足仍可形成正式 Finding。

### 权限语义

角色权限是“不得改变被审查候选版本”，而不是禁止所有临时写入。

Verifier 可以：

- 在独立、可丢弃的验证 Worktree 中读取代码；
- 运行测试、构建、Lint、类型检查和必要程序；
- 生成缓存、覆盖率、构建产物和临时文件；
- 请求一个窄范围 Specialist 判断；
- 返回结构化 `REVIEW_REPORT`。

Verifier 不可以：

- 主动修改被跟踪源文件；
- 创建 Commit；
- 切换分支或改变 HEAD；
- 修改项目控制文件；
- 直接命令 Builder；
- 自行创建 Specialist；
- 自行改变验收标准；
- 宣布整个里程碑或 Goal 最终完成。

## 4.4 临时 Specialist

Specialist 是受控咨询能力，不是正式角色。

必须满足：

```text
一个明确问题
一个获批 SPECIALIST_ORDER
一个固定 Evidence SHA
一个独立可丢弃 Worktree
一个结构化最终报告
```

Specialist：

- 默认只读指定文件、Diff、测试与 Evidence；
- 不继承请求方完整会话；
- 不扫描整个仓库；
- 不修改业务代码、测试或控制文件；
- 不创建 Commit、切换分支或改变 Candidate；
- 不直接命令 Builder、Verifier；
- 不制定完整实施方案；
- 不输出具有状态机效力的 `ACCEPT / REWORK / BLOCKED`；
- 不创建下级 Subagent；
- 信息不足时最多返回一次 `EVIDENCE_NEEDED`；
- 完成 `FINDING` 或 `UNRESOLVED` 后立即结束。

静态证据不足且诊断会改变结论时，可以执行与问题绑定的最小诊断命令；不得安装依赖、访问生产环境、真实客户数据、外部账号或执行不可逆操作。

## 4.5 单一事实源与独立最小上下文

```text
Goalkeeper 上下文
= 用户目标 + 权威控制文件 + Git 元数据 + 少量合同级证据

Builder 上下文
= WORK_ORDER + Base/Candidate 差量 + 目标代码 + 必要项目规则

Verifier 上下文
= VERIFY_ORDER + 固定 Candidate Diff + 有效证据 + 必要相关代码

Specialist 上下文
= SPECIALIST_ORDER + 固定 SHA + 指定文件/证据
```

角色共享的是结构化事实，不共享完整聊天或模型推理过程。

---

# 5. 触发与运行模式

## 5.1 只允许显式调用

Skill 元数据必须配置：

```yaml
policy:
  allow_implicit_invocation: false
```

支持的调用方式示例：

```text
$project-flight-control
$project-flight-control START
$project-flight-control RESUME
$project-flight-control AUDIT
$project-flight-control STATUS_ONLY
```

## 5.2 模式优先级

用户未指定时，Goalkeeper 先只读判断：

```text
STATUS_ONLY
→ AUDIT
→ RESUME
→ START
```

这些是控制流程模式，不是任务复杂度或 Token 模式。

### START

适用于：

- 新项目；
- 新的大型功能；
- 尚无稳定 Goal、Roadmap 或实现；
- 预计跨多个任务或多个 Codex 回合。

### RESUME

适用于：

- 已有代码或计划；
- 从中断、旧会话或现有项目接管；
- 控制文件、路线和代码需要重新校准。

### AUDIT

适用于：

- 里程碑声称完成；
- 用户担心项目跑偏；
- 新证据可能改变路线；
- 准备进入下一个里程碑；
- Goal 级最终审计。

### STATUS_ONLY

适用于：

- 只查询当前进度、剩余工作、阻塞和预测；
- 严格只读；
- 不修改代码；
- 不修改控制文件；
- 不创建 Builder、Verifier 或 Specialist。

## 5.3 模式冲突

如果用户指定模式与项目事实明显冲突：

- 不静默切换；
- 不执行写入；
- 说明事实冲突与建议模式；
- 取得用户决定后继续。

## 5.4 不设置复杂度模式

V1 不提供：

```text
FAST
STANDARD
DEEP
SIMPLE
COMPLEX
```

普通小任务通过不调用本 Skill 处理。用户显式调用后，始终保持三角色隔离，但每个角色的合同、读取和验证规模可按真实风险自然缩放。

---

# 6. 项目事实源与控制文件

## 6.1 单一事实源原则

Goalkeeper 先识别已有文件：

```text
README.md
PRD.md
SPEC.md
PLAN.md
ROADMAP.md
BACKLOG.md
PROGRESS.md
STATUS.md
DECISIONS.md
docs/adr/
```

对每类事实只能指定一个权威来源：

```text
Goal / Scope
Roadmap / Milestones
Current State
Decisions
Evidence
```

不得复制同一份目标、路线、合同、风险或收敛状态到第二套文件中。

## 6.2 缺省结构

只有项目不存在等价来源时，才创建：

```text
docs/project-control/
├─ PROJECT.md
├─ ROADMAP.md
├─ STATUS.md
├─ DECISIONS.md
└─ evidence/
```

V1 不创建：

```text
DISCOVERY_REPORT
debug-history.md
convergence-log.md
risk-register.md
waiver-log.md
token-usage.json
repo-map 或语义索引数据库
```

## 6.3 STATUS.md 必备字段

```text
Updated At
Control Run ID
Lease Epoch
Canonical Project Sources
Goal ID
Goal Version
Goal State
Milestone ID
Milestone Contract Version
Milestone State
Current Owner
Current Lease
Base SHA
Latest Candidate SHA
Current Revision
Goal Code SHA
Goal Checkpoint SHA
Latest Valid Build Report
Latest Valid Review Report
Latest Evidence IDs
Open Blocking Findings
Repair Rounds Used
Builder Internal Repair State
Convergence Snapshot
Pending Decision
Next Authorized Action
Done
In Progress
Next
Blockers
New Findings
Scope Change
Roadmap Change
Forecast
Forecast Confidence
Previous Thread IDs
Builder Worktree State
Verifier Worktree State
Specialist State
Active Specialist Order ID
Latest Specialist Report ID
Specialist Evidence SHA
Specialist Guidance Status
Specialist Worktree State
Milestone Branch State
Cleanup Result
```

`Convergence Snapshot` 只保存最新控制快照；历史事实继续由对应 `BUILD_REPORT`、`REVIEW_REPORT` 和 Evidence 承载。

## 6.4 写入规则

- Goalkeeper 是控制文件唯一写入者；
- Builder、Verifier 与 Specialist 只读控制文件；
- Builder、Verifier 通过结构化消息申请修正、专业判断或合同变化；
- Specialist 只通过 `SPECIALIST_REPORT` 回传；
- 决策记录采用追加式历史；
- 不删除旧失败记录来制造“干净状态”；
- 不持久化任何角色的完整内部推理或完整聊天；
- 敏感信息不得进入控制文件或 Evidence。

---

# 7. Goal 与 Milestone 合同

## 7.1 Goal Contract

至少包含：

```text
Goal ID
Goal Version
项目名称
要解决的问题
目标用户或使用者
最终目标
成功标准
明确非目标
关键约束
不可做事项
结束条件
暂停条件
终止条件
批准记录
```

## 7.2 Milestone Contract

每个里程碑必须包含：

```text
Milestone ID
Contract Version
Parent Milestone
Parent Accepted Checkpoint SHA
目标结果
为什么需要该里程碑
允许范围
明确非目标 / 禁止范围
关键约束
依赖
验收标准
Required Verification
所需证据
Baseline Observations
Evidence References
Unverified Assumptions
主要风险
Approved Base SHA
初始工作量区间
当前状态
批准记录
```

### Baseline Observations

只保存形成合同所必需的现状：

```text
已有相关能力
当前缺失行为
直接兼容性或数据边界
已确认风险
仍需 Builder 验证的假设
```

### Evidence References

只保存可重新定位的最小引用：

```text
Base SHA
文件 / 模块 / 测试 / 配置入口
必要行段或符号
已有 Evidence ID
```

不得保存 Goalkeeper 的完整分析过程或逐函数实现方案。

## 7.3 Execution Contract 与最小投影

`Execution Contract` 是 Milestone Contract 在运行流程中的语义名称，不是新文件。

```text
Milestone Contract
= 唯一权威合同

Milestone Contract
├─ 最小投影 → WORK_ORDER
└─ 最小投影 → VERIFY_ORDER
```

`WORK_ORDER` 只包含 Builder 完成当前实现所需的字段；`VERIFY_ORDER` 只包含 Verifier 独立验收所需的字段。两者不得复制无关项目历史。

合同发生实质变化时：

```text
Contract Version +1
→ 旧 WORK_ORDER / VERIFY_ORDER 失效
→ 重新生成受影响投影
→ 重新执行 Alignment Audit
→ 重新验证受影响部分
```

## 7.4 合同级侦察

START 或重大 RESUME 时，Goalkeeper 可以进行一次受限侦察。只有 Base、合同或用户目标发生实质变化，才允许重新侦察受影响部分。

侦察只回答：

```text
要完成什么？
不能改变什么？
怎样才算通过？
现有项目是否已有部分能力？
是否存在数据、兼容性或安全边界？
是否需要用户决定？
```

侦察不足时暂停并请求必要决定，不得无限扩大为实现级分析。

## 7.5 单一激活原则

任一时刻只允许：

```text
Current Goal：1 个
Active Milestone：1 个
```

同一里程碑内可以拆分多个 Work Package，但只有真正独立、无共享写入和无顺序依赖时才能并行。V1 的正式 Builder 与 Verifier 流程仍采用中心式串行交接。

## 7.6 开发开始门槛

START 或重大 RESUME 在实施前必须向用户展示：

```text
目标
非目标
路线图
当前里程碑
验收标准
Required Verification
主要风险
未验证假设
初始剩余工作预测
```

获得批准后才进入 `ACTIVE`。

---

# 8. 状态模型

## 8.1 运行模式

```text
START
RESUME
AUDIT
STATUS_ONLY
```

## 8.2 里程碑状态

```text
PLANNED
READY
ACTIVE
REVIEW
REPAIR
BLOCKED
CHANGED
ACCEPTED
CANCELLED
ACCEPTANCE_CHECKPOINT_INVALID
```

Specialist 是里程碑中的同步子状态，不新增独立里程碑终态。

## 8.3 验证结果

```text
PASS
FAIL
PARTIAL
NOT_RUN
```

## 8.4 Goal 状态

```text
PLANNED
ACTIVE
GOAL_REVIEW
GOAL_REPAIR
BLOCKED
CHANGED
GOAL_ACCEPTED
PROJECT_COMPLETE
CANCELLED
```

## 8.5 Specialist 子状态

```text
NONE
REQUESTED
ACTIVE
EVIDENCE_NEEDED
RESOLVED
UNRESOLVED
UNAVAILABLE
```

当 Specialist 为当前验收必要前提时，`ACTIVE / EVIDENCE_NEEDED / UNRESOLVED / UNAVAILABLE` 均阻止相关正式 Verdict；非必要咨询不得无意义阻断其他已获证明的合同内容。

## 8.6 完成语义

```text
IMPLEMENTED
= Builder 已提交 Candidate。

VERIFIED
= Verifier 已对精确 Candidate 给出有效 PASS。

MILESTONE_ACCEPTED
= Goalkeeper 已确认里程碑合同、证据和航向均满足。

GOAL_ACCEPTED
= 最终累计版本通过全新的 Goal 级最终审计。

PROJECT_COMPLETE
= Goal 已验收，且必要集成、交付与收尾事项也已完成。
```

`GOAL_ACCEPTED` 不表示已经 Push、Merge、发布或部署。

## 8.7 效率语义

```text
EFFICIENCY_EXCEPTION
≠ FAIL
≠ BLOCKER
≠ 自动返工
```

只有效率偏离形成仍存在的范围违规、重复实现、不必要依赖、过度抽象、回归或证据不足时，才按可观察交付缺陷处理。已经发生且无法追回的过程浪费，不通过重新执行正确任务来“处罚”。

---

# 9. Git 基线与安全边界

## 9.1 Git 强制前提

### START / RESUME

需要修改代码时必须满足：

```text
Git Repository：YES
Base Commit：AVAILABLE
Candidate Commit：AVAILABLE
```

### AUDIT

非 Git 项目可做有限只读审查，但：

```text
Candidate Identity：UNAVAILABLE
Version Integrity：NOT_VERIFIABLE
Final Result：最多 PARTIAL
Milestone：不得 ACCEPTED
```

### STATUS_ONLY

可以执行，但必须报告：

```text
Version Control：NOT_CONFIGURED
Evidence Reliability：LIMITED
```

## 9.2 原工作区基线检查

创建里程碑 Worktree 前检查：

```text
Current Branch
Current HEAD
Modified Files
Untracked Files
Merge / Rebase / Cherry-pick / Revert / Bisect State
User-Specified Base Branch / SHA
```

基线选择顺序：

1. 用户明确指定的 Base SHA；
2. 用户明确指定分支的当前 Commit；
3. 调用 Skill 时原工作区的 HEAD。

## 9.3 原工作区存在未提交改动

必须暂停并输出：

```text
BASELINE_DECISION_REQUIRED
```

允许用户选择：

```text
A. 使用当前 HEAD，明确排除未提交改动；
B. 用户先整理并提交需要纳入的改动；
C. 指定另一个 Branch 或 SHA。
```

Skill 不得自动执行：

```text
git add
git stash
git clean
git reset
提交用户原有改动
复制未提交文件到里程碑 Worktree
```

## 9.4 允许的本地 Git 操作

经用户批准当前里程碑后：

- Goalkeeper 可以创建控制记录 Commit；
- Builder 可以创建本地里程碑分支和 Candidate Commit；
- 每轮返工可以产生新的 Revision Commit；
- Verifier 不创建 Commit。

## 9.5 禁止的 Git 与交付操作

未经额外明确授权，禁止：

```text
git push
Merge 到正式分支
创建或合并远程 PR
rebase
reset --hard
force push
删除分支或标签
修改远程配置
发布
部署
生产环境变更
```

Commit 权限不等于 Merge 权限。

---

# 10. Worktree 拓扑与写入租约

## 10.1 固定拓扑

```text
用户原始 Worktree
└─ Skill 不修改、不切换分支、不清理

里程碑 Worktree
├─ Goalkeeper：仅控制文件写入阶段
└─ Builder：仅实现与返工阶段
   两者分时使用

Verifier Worktree
└─ 固定 Candidate SHA，独立验证

Specialist Worktree（仅按需创建）
└─ 固定 Base SHA / Candidate SHA，临时专业分析
```

Specialist Worktree 不复用 Builder 或 Verifier Worktree。

## 10.2 写入租约

普通闭环：

```text
GOALKEEPER_LEASE
→ BUILDER_LEASE
→ GOALKEEPER_LEASE
→ VERIFICATION_IN_PROGRESS
→ GOALKEEPER_LEASE
```

Builder 阶段调用 Specialist：

```text
BUILDER_LEASE
→ Builder 停止受影响修改并交回租约
→ GOALKEEPER_LEASE
→ SPECIALIST_IN_PROGRESS（独立 Worktree）
→ GOALKEEPER_LEASE
→ 恢复或修订 WORK_ORDER
```

Verifier 阶段调用 Specialist：

```text
Candidate 保持冻结
→ VERIFICATION_PAUSED_FOR_SPECIALIST
→ SPECIALIST_IN_PROGRESS（独立 Worktree）
→ Goalkeeper 校验报告
→ Verifier 继续独立验证
```

强制规则：

- 同一里程碑 Worktree 任一时刻只能有一个写入者；
- Builder 未交回租约时，Goalkeeper 不写入；
- Goalkeeper 未完成持久化时，不发下一轮返工；
- Candidate 验证和 Specialist 咨询期间，相关 Evidence SHA 必须冻结；
- Specialist 不取得里程碑 Worktree 写入租约；
- Specialist 影响的实施或验证必须同步暂停；
- 租约不明确时立即暂停。

## 10.3 Verifier Worktree

要求：

```text
Checked Out：Candidate SHA
HEAD：detached
Permission：验证工作区与临时目录受限可写
Git Commit：禁止
Branch Switch：禁止
Tracked Source Modification：禁止
```

验证前后必须检查：

```text
HEAD 是否仍等于 Candidate SHA
git diff --exit-code
git diff --cached --exit-code
git status --porcelain
```

结果处理：

```text
跟踪文件未变化 → 验证有效
仅声明过的缓存或临时产物 → 登记后继续
测试工具修改跟踪文件 → REVIEW_INVALID
HEAD/索引/分支变化 → VERSION_INTEGRITY_FAIL
无法创建独立 Worktree → BLOCKED_BY_ENVIRONMENT
```

不得静默退化为与 Builder 共用工作区。

## 10.4 Specialist Worktree

每个获批的 `SPECIALIST_ORDER` 创建一个独立、可丢弃 Worktree：

```text
Checked Out：SPECIALIST_ORDER.Evidence SHA
HEAD：detached
Branch：不创建长期分支
Default Permission：read-only
Tracked Source Modification：禁止
Git Commit：禁止
Branch Switch：禁止
Network：默认禁止
```

允许的临时写入只限于：

- 操作系统临时目录；
- 明确可丢弃的工具缓存；
- 已确认不会改变跟踪文件的忽略路径。

Specialist 开始和结束时必须验证：

```text
实际 HEAD = Evidence SHA
无 staged changes
无 tracked source changes
诊断命令未改变候选版本
```

若诊断工具修改跟踪文件、索引或 HEAD：

```text
SPECIALIST_REPORT_INVALID
```

不得把该环境产生的结论作为正式专业证据。

---

# 11. 版本与证据链

## 11.1 Candidate SHA

由 Builder 创建，代表 Verifier 实际验证的实现版本。

```text
Base SHA
└─ Candidate SHA C1
   ├─ 业务代码
   ├─ 测试
   └─ 当前 Work Order 的实现
```

所有技术结果绑定：

```text
Verified Candidate SHA：C1
```

Builder 的验证证据必须明确说明命令是在形成 Candidate 前还是在 Candidate 上执行；若 Candidate 在验证后变化，受影响证据失效并需重新执行。

## 11.2 控制记录 Commit

Goalkeeper 可以在 Candidate 后追加仅包含控制记录的 Commit，用于持久化：

- Build Report；
- Review Report；
- Specialist Order / Report；
- Decision；
- Status；
- 紧凑 Evidence Record 与必要附件索引。

控制记录 Commit 不是新的 Candidate，不得被描述成已完成技术验证的实现版本。

## 11.3 Accepted Checkpoint SHA

Verifier 对最终 Candidate 给出有效 PASS 后，Goalkeeper 只追加治理与验收记录，形成：

```text
Candidate SHA Cn
└─ Accepted Checkpoint SHA An
```

`Cn..An` 的差异只能位于 Canonical Project Sources 中登记的控制文件路径。

不得包含：

- 业务源代码；
- 测试实现；
- 构建或运行配置；
- 依赖锁文件；
- 数据库或迁移代码；
- 未登记文件。

出现越界：

```text
Acceptance Checkpoint：INVALID
Milestone State：ACCEPTANCE_CHECKPOINT_INVALID
```

## 11.4 里程碑继承

下一里程碑的：

```text
Base SHA = 上一里程碑 Accepted Checkpoint SHA
```

同时记录：

```text
Goal Code SHA
= 最近通过验证的累计业务实现版本

Goal Checkpoint SHA
= Goal Code SHA + 最新控制与验收记录
```

只有 `ACCEPTED` 的 Checkpoint 才能成为下一里程碑基线。

## 11.5 紧凑 Evidence Record

每次具有验收意义的命令或人工验证，默认保存一条紧凑记录：

```text
Evidence ID
Candidate SHA
Source：AGENT_EXECUTED / USER_EXECUTED / EXTERNAL_SYSTEM
Command / Verification Action
Working Directory
Environment
Exit Code / Result Claimed
Observed Result
Covered Criteria
Created At
Evidence Location（仅有附件时）
```

成功验证默认只保存：

```text
实际命令或动作
退出码
结果摘要
覆盖的验收项
Candidate SHA
```

不得把完整终端日志复制进 `WORK_ORDER`、`BUILD_REPORT`、`VERIFY_ORDER`、`REVIEW_REPORT` 或角色交接消息。

## 11.6 受限证据附件

仅在以下情况保存附件：

- 测试、构建或运行失败；
- `BLOCKER / MAJOR` 需要具体输出支撑；
- 偶发、环境相关或难以复现的问题；
- 人工或外部系统验证；
- 摘要不足以证明关键验收项；
- 中断恢复确实需要关键输出。

附件必须：

```text
只保留相关错误段、失败用例和必要环境信息
绑定 Evidence ID 与 Candidate SHA
设置明确且有限的体积与行数上限
脱敏 Token、Cookie、密钥、账号、客户数据和敏感路径
不覆盖旧证据
不把无关完整日志提交进 Git
```

批量 Raw Logs 默认只是临时运行产物，不是恢复所需的唯一事实源。

## 11.7 Specialist Evidence 与 Guidance

Specialist 实际观察到的事实严格绑定：

```text
SPECIALIST_ORDER.Evidence SHA
```

Candidate 变化后，旧报告不能证明新 Candidate 已安全、已修复或已通过。

Goalkeeper 可以对报告中的建议进行适用性检查：

```text
GUIDANCE_APPLICABLE
GUIDANCE_PARTIALLY_APPLICABLE
REPORT_STALE
```

判断依据：

- 新 Diff 是否改变原证据范围；
- 合同、依赖、配置或数据模型是否变化；
- 核心假设是否仍成立；
- 引用的是实现方向，还是错误地把旧事实套用到新版本。

专业建议可以继续作为参考，但新 Candidate 的正确性必须由新的 Builder 证据和 Verifier 独立复验建立。

---

# 12. 结构化通信协议

## 12.1 正式消息类型

```text
WORK_ORDER
BUILD_REPORT
VERIFY_ORDER
REVIEW_REPORT
REWORK_ORDER
SPECIALIST_REQUEST
SPECIALIST_ORDER
SPECIALIST_REPORT
CHANGE_REQUEST
STATE_CORRECTION_REQUEST
ROADMAP_CHANGE_REQUEST
HUMAN_VERIFICATION_REQUEST
HUMAN_VERIFICATION_RESPONSE
DECISION_PACKET
DECISION
ACCEPTANCE_REPORT
FINAL_REVIEW_REPORT
PROJECT_CONTROL_REPORT
```

`EFFICIENCY_EXCEPTION`、`DEBUGGING_SUMMARY`、`CONVERGENCE_SNAPSHOT` 和 `EVIDENCE_RECORD` 是对应报告或状态中的结构化对象，不额外扩张为独立对话流程。

## 12.2 通用身份字段

所有正式工作单和报告必须包含：

```text
Control Run ID
Lease Epoch
Goal ID
Goal Version
Milestone ID
Milestone Contract Version
Revision
Base SHA / Candidate SHA / Evidence SHA（按消息类型）
Sender Role
Recipient Role
Created At
```

字段缺失、Epoch 过期、版本不匹配或 SHA 不一致时：

```text
REPORT_REJECTED
```

旧线程迟到回执：

```text
STALE_REPORT_REJECTED
```

## 12.3 WORK_ORDER 必填字段

`WORK_ORDER` 是 Milestone Contract 面向 Builder 的最小投影：

```text
Work Order ID
Goal / Target Result
Authorized Scope
Non-goals / Forbidden Scope
Constraints
Dependencies
Acceptance Criteria
Base SHA
Required Verification
Relevant Baseline Observations
Relevant Evidence References
Known Risks
Expected Evidence
Revision
```

不得重复整份 Goal、Roadmap、项目历史或 Builder 核心效率协议。

## 12.4 BUILD_REPORT 必填字段

```text
Work Order ID
Base SHA
Candidate SHA
Changed Files
Implemented Criteria
Commands Run
Observed Results
Verification Status
NOT_RUN Items
Known Limitations
Scope Deviations
Open Risks
Evidence IDs / Locations
Efficiency Exception（仅适用时）
Debugging Summary（仅适用时）
Convergence Inputs
```

每条命令至少记录：

```text
Command
Working Directory
Candidate SHA
Exit Code
Observed Result
Covered Criteria
NOT_RUN Reason（如适用）
Evidence ID
```

`EFFICIENCY_EXCEPTION` 字段：

```text
Trigger
Action
Reason
Affected Scope
```

没有例外时不输出固定效率清单。

`DEBUGGING_SUMMARY` 字段：

```text
Failure Signature
Reproduction
Evidence
Hypotheses Tested
Repair Attempts
Current Understanding
Remaining Unknown
Recommended Next Action
```

## 12.5 VERIFY_ORDER 必填字段

`VERIFY_ORDER` 是 Milestone Contract 面向 Verifier 的最小投影：

```text
Verify Order ID
Acceptance Criteria
Constraints
Base SHA
Candidate SHA
Changed Files
Required Verification
Builder Evidence IDs
Known Risks
Relevant Specialist Order / Report IDs
Required Independent Checks
Revision
```

不得附带 Builder 完整聊天、内部推理或无关失败日志。

## 12.6 REVIEW_REPORT 必填字段

```text
Candidate SHA
Alignment Result
Evidence Integrity Result
Technical Result
Environment
Builder Evidence Reused
Independent Commands Run
Observed Results
Version Integrity
Findings
Residual Risks
Specialist Dependency Status
Verdict
```

`Builder Evidence Reused` 必须说明哪些证据已验证可复用；`Independent Commands Run` 必须列出 Verifier 自己执行的最小独立复验。

## 12.7 DECISION 必填字段

```text
Decision：ACCEPTED / REPAIR / BLOCKED / CHANGED
Evidence Basis
Required Repairs
Non-blocking Backlog Items
Residual Risk（仅适用时）
Contract Change（仅适用时）
Scope Impact
Roadmap Impact
Forecast Impact
Next Authorized Action
```

合同变化时还必须包含：

```text
Previous Contract Version
New Contract Version
User-approved Change
Verification Invalidated
```

接受非阻断残余风险时还必须包含：

```text
Risk
Why Non-blocking
Accepted By
Affected Scope
Future Action
```

## 12.8 SPECIALIST_REQUEST

由 Goalkeeper、Builder 或 Verifier 提出：

```text
Request ID
Requester
Question
Why Specialist Is Required
Decision Affected
Evidence SHA
Relevant Acceptance Criteria
Relevant Scope
Known Evidence
```

它只是申请，不自动创建 Specialist。Builder 与 Verifier不得自行派生子智能体。

## 12.9 SPECIALIST_ORDER

Goalkeeper 批准后生成，作为 Specialist 唯一正式输入：

```text
Specialist Order ID
Request ID
Specialist Perspective
Question
Decision Affected
Evidence SHA
Allowed Files / Symbols / Evidence
Known Evidence
Allowed Diagnostic Action
Evidence Round：0 / 1
Required Output
```

同一问题最多一次证据补充。补充后仍使用同一个 `Specialist Order ID`，仅把 `Evidence Round` 从 `0` 修订为 `1`。

## 12.10 SPECIALIST_REPORT

统一状态：

```text
FINDING
EVIDENCE_NEEDED
UNRESOLVED
```

### FINDING

```text
Specialist Report ID
Specialist Order ID
Question
Evidence SHA
Finding
Evidence
Risk
Recommendation
Confidence
Diagnostics Run
```

### EVIDENCE_NEEDED

```text
Specialist Report ID
Specialist Order ID
Evidence SHA
Missing Evidence
Why Required
Requested Scope
Requested Diagnostic
Risk
```

只能出现一次。

### UNRESOLVED

```text
Specialist Report ID
Specialist Order ID
Evidence SHA
Known
Unknown
Evidence Reviewed
Why Unresolved
Decision Risk
Recommended Next Action
```

Specialist 不得输出具有正式状态机效力的 `ACCEPT / REWORK / BLOCKED`。

## 12.11 Specialist 持久化边界

默认持久化：

```text
已批准的 SPECIALIST_ORDER
最终 SPECIALIST_REPORT
被正式引用的紧凑 Evidence Record
```

默认不持久化：

```text
Specialist 完整聊天
内部推理过程
临时探索记录
无关命令输出
未影响任务推进的普通拒绝申请
```

若 Specialist 结论影响 `WORK_ORDER`、`VERIFY_ORDER`、`REWORK_ORDER`、合同或正式 `DECISION`，Goalkeeper必须引用 Specialist Order ID、Report ID 和 Evidence SHA。

---

# 13. Verifier Finding、证据与裁决

## 13.1 严重度

### BLOCKER

- 核心验收标准失败；
- 无法构建或运行；
- 数据损坏、安全、权限风险；
- 版本完整性不可确认；
- 明显偏离批准目标；
- 验收必要的 Specialist 问题仍未解决且无法由其他证据证明。

处理：始终阻断 `ACCEPTED`。

### MAJOR

- 重要用户场景缺失；
- 关键边界失败；
- 重要错误处理缺失；
- 必需测试或证据不足；
- 与 Work Order 存在明显差异；
- 对兼容性或维护造成实质影响；
- 重复实现、不必要依赖或过度抽象已形成实际范围、回归或维护问题。

处理：默认阻断。修复，或由用户批准合同变化后重新审计。

### MINOR

- 不影响行为的命名或格式建议；
- 非当前范围结构优化；
- 低风险维护建议；
- 不影响验收标准的测试增强。

处理：不阻断，进入 Backlog 或 Residual Risks。

## 13.2 阻断 Finding 必填字段

```text
Finding ID
Finding Type
Severity
Candidate SHA
Related Acceptance Criterion / Constraint / Objective Risk
Expected Result
Observed Result
Reproduction / Command
Evidence
Impact
Blocking Reason
Suggested Direction
```

以下内容不能单独作为阻断依据：

```text
“实现不够优雅”
“最好顺便重构”
“未来可能有问题”
“我更喜欢另一种写法”
“Builder 可能多读了几个文件”
“这个过程看起来不够省 Token”
```

## 13.3 约束力

满足以下条件的 `BLOCKER / MAJOR` 是：

```text
VALID_BLOCKING_FINDING
```

条件：

```text
Candidate SHA 正确
+ 关联明确验收标准、约束或客观风险
+ 证据完整
+ 可复现或有可靠运行结果
```

Goalkeeper 不得直接忽略、降级或推翻。

允许的处理只有：

```text
REPAIR
BLOCKED
CHANGED
REVIEW_CLARIFICATION
INDEPENDENT_RECHECK
```

## 13.4 默认独立验证路径

Verifier 首先校验 Builder 证据：

```text
实际命令和退出码是否存在
证据是否绑定当前 Candidate SHA
Candidate 在验证后是否变化
命令是否覆盖声明的验收项
输出是否完整、可信且已脱敏
BUILD_REPORT 与真实 Diff 是否一致
```

证据有效后，不机械重复所有命令，但必须完成最小独立复验：

```text
1. Candidate 版本完整性；
2. 核心变更的目标测试或运行检查；
3. 曾经失败、当前声称已修复的验证；
4. Verifier 从 Diff 识别的高风险边界。
```

以下情况必须扩大或重跑相关验证：

- 证据未绑定 Candidate SHA；
- Candidate 在验证后变化；
- 命令、退出码或输出不完整；
- 涉及数据迁移、安全、权限、并发或不可逆行为；
- 测试不稳定或环境依赖明显；
- Diff 与 Builder 报告不一致；
- 影响范围被低估；
- Specialist Finding 要求额外证明；
- 项目规则明确要求独立重跑。

## 13.5 独立复验争议

出现证据冲突、环境冲突、严重度争议或原审查过程可能无效时：

- 创建全新的 Verifier Thread；
- 创建新的验证 Worktree；
- 固定同一 Candidate SHA；
- 不继承原 Verifier 推理过程；
- 不提示新 Verifier 应支持哪一方。

结果：

```text
问题被复现 → Finding 保持有效
无法复现且反证充分 → INVALIDATED，保留原记录
环境结果冲突 → BLOCKED_BY_ENVIRONMENT_CONFLICT
合同歧义 → CHANGED
复验完整性失败 → RECHECK_INVALID
```

## 13.6 Specialist 未解决问题

`SPECIALIST_REPORT.Status = UNRESOLVED` 时，Verifier 判断该问题是否为当前合同的验收必要前提。

必要前提包括：

- 直接关系核心验收标准；
- 涉及数据损坏、权限提升、安全边界；
- 影响版本完整性、迁移或恢复能力；
- 合同明确要求该专业结论；
- 缺少结论就无法排除重大回归；
- 无法由其他独立证据完成判断。

必要前提未解决：

```text
Verifier 不得 PASS
Goalkeeper 不得 ACCEPTED
```

非必要问题且已有其他充分证据时，可以作为 `RESIDUAL_RISK`，不得触发顺手扩展。记录必须说明为什么不阻断、证据依据和未来动作。

---

# 14. Builder 调试、自动返工与收敛

## 14.1 Builder 内部调试协议

Builder 只有在测试、构建或实际行为失败时才加载 `builder-debugging.md`：

```text
读取最小失败证据
→ 稳定复现
→ 检查本轮变更与相关调用路径
→ 提出单一根因假设
→ 用最小动作验证假设
→ 修复已确认根因
→ 重跑受影响验证
```

禁止：

```text
同时叠加多个猜测性补丁
跳过根因调查直接试改
删除测试或降低断言
失败后无新证据继续扩大修改
```

## 14.2 Builder 内部修复上限

针对同一失败现象或同一根因路径，最多进行两次改变业务代码、测试或配置的修复尝试：

```text
Failure
→ Repair Attempt 1
→ Verify
→ 新证据与新假设
→ Repair Attempt 2
→ Verify
→ 仍不收敛：停止并交回 Goalkeeper
```

不计入修复尝试：

- 为确认偶发性而重复运行同一命令；
- 修正错误的命令、测试路径或参数；
- 清理缓存或恢复测试环境；
- 不改变业务行为的格式化；
- 一个修复成功后暴露出的全新、独立失败；
- 环境恢复后的首次重新验证。

两次后仍不通过，Builder 必须返回 `FAIL / PARTIAL` 和 `DEBUGGING_SUMMARY`，不得通过轻微改写错误描述把同一问题伪装成新失败。

## 14.3 正式返工链

```text
R1：首次 Candidate
R2：第 1 次自动返工
R3：第 2 次自动返工
```

```text
R1 FAIL → R2
R2 FAIL → R3
R3 FAIL → REPAIR_LOOP_STOPPED
```

Builder 内部修复尝试与正式 Revision 分别计数；一次普通局部修复不自动消耗完整 Revision。

## 14.4 跨 Revision 收敛快照

每个 Revision 后，由 Goalkeeper从 `BUILD_REPORT` 与 `REVIEW_REPORT` 提取：

```text
CONVERGENCE_SNAPSHOT
Revision
Candidate SHA
Blocking Findings
Passed Criteria
Remaining Failed Criteria
Failure Signature
New Evidence Since Previous Revision
Trend
Next Authorized Action
```

`Trend` 只允许：

```text
IMPROVING
STALLED
REGRESSING
UNKNOWN
```

`STATUS.md` 只保存最新快照；历史报告保存每轮事实，不新增独立收敛日志。

## 14.5 跨 Revision 提前停止门禁

每轮后检查：

- 原 Finding 是否减少或消失；
- 失败范围是否缩小；
- 新通过的验收项是否增加；
- 是否获得新的根因证据；
- 是否只是更换错误表现而没有推进；
- 是否持续修改同一区域却没有新增有效证据；
- 是否出现新的高风险回归；
- 是否开始在多个方案或模块之间来回摆动；
- 继续执行是否需要专业判断或合同变化。

任一条件满足可提前停止：

```text
同一核心失败跨两个 Revision 持续存在
连续两轮没有新增通过的验收项
Finding 数量和严重度没有下降
Builder 缺少新的根因证据
修复在多个方向之间摆动
继续实施需要扩大合同范围
必要 Specialist 能力不可用或结论未解决
```

停止后由 Goalkeeper选择：

```text
创建 Specialist
请求用户决定
调整或拆分合同
标记 BLOCKED
```

## 14.6 效率例外与返工

`EFFICIENCY_EXCEPTION` 本身不自动产生返工。

处理：

```text
合理且必要的扩大
→ 接受并继续验证

不合理但未影响候选结果
→ 记录过程偏离，不重新执行正确任务

形成可观察交付问题
→ 按范围、质量、依赖、回归或证据 Finding 返工

构成实质合同变化
→ CONTRACT_CHANGE_REQUIRED
```

不为已经发生且不可追回的 Token 消耗制造二次返工。

## 14.7 追加轮次

用户可以明确发送：

```text
AUTHORIZE_ONE_MORE_REPAIR_ROUND
```

每次只增加一轮，并且必须存在新的证据、实质不同的修复路径或已批准合同变化；不得授权无限返工。

---

# 15. 合同变更与残余风险

## 15.1 Goalkeeper 可自主处理

不改变目标和验收含义的运行级调整：

- 修正文档错字和格式；
- 拆分或重排当前里程碑内部工作单；
- 增加当前验收标准所需测试；
- 登记当前实现造成的 Repair；
- 更新状态、证据、收敛快照和预测；
- 补充不改变产品行为的验证步骤；
- 将 MINOR 加入 Backlog；
- 修正可由现有证据证明的过期状态；
- 接受不会改变合同的合理 `EFFICIENCY_EXCEPTION`；
- 将已批准 Specialist 的建议投影到工作单或验证单。

## 15.2 必须由用户批准

- 最终目标、非目标或成功标准变化；
- 验收标准增加、删除、弱化或重新解释；
- 用户可见行为或产品承诺变化；
- 功能范围扩大或缩小；
- 新增、删除或实质调整里程碑；
- 关键顺序或关键路径变化；
- 公共 API、数据模型或兼容性变化；
- 重大架构变化；
- 数据迁移、删除或不可逆转换；
- 安全、权限、认证、凭据或隐私边界变化；
- 新生产依赖、外部服务或付费服务；
- 预算、发布条件或部署范围变化；
- 预测相较批准基线显著增加；
- 为响应有效 `BLOCKER / MAJOR` 而改变原合同；
- 取消或替换当前 Goal。

## 15.3 用户不能把证据缺口豁免为 PASS

```text
风险接受
≠ 证据证明
≠ 验收通过
```

当前合同的必要前提仍为 `NOT_PROVEN` 时，用户不能在不修改合同的情况下直接把该验收项标记为 PASS。

用户可以：

1. 补充自动化、人工或外部证据；
2. 正式修改 Milestone Contract；
3. 把可证明与未证明部分拆为不同里程碑；
4. 接受已经由 Verifier 判定为非阻断的残余风险。

以下已知失败不得仅通过删除标准制造 PASS：

- 已知数据损坏；
- 明确凭据泄露；
- 确认存在的权限绕过；
- 被破坏的版本完整性；
- 无法构建或运行却声称交付可用；
- 伪造、缺失或错配的验证证据。

用户可以选择停止、延期或接受未交付状态，但 Skill 不得把已知失败改写为成功。

## 15.4 合同变更处理

```text
暂停 Builder
暂停连续模式
输出 Decision Packet
等待用户明确批准
更新 Milestone Contract Version
旧 WORK_ORDER / VERIFY_ORDER 失效
重新执行 Alignment Audit
重新验证受影响标准
```

Milestone Contract 当前版本至少记录：

```text
Contract Version
Changed Fields
Change Reason
Approved By
Supersedes Version
Effective Base / Candidate SHA
Affected Verification
```

旧版本由 Git 历史保留，不另建合同历史文件。

同时生成：

```text
DECISION
Decision：CHANGED
Previous Contract Version
New Contract Version
User-approved Change
Reason
Scope Impact
Verification Invalidated
Next Authorized Action
```

## 15.5 非阻断残余风险接受

只有当前合同已被充分证明，且 Verifier确认风险不属于当前必要前提时，用户才可以接受：

```text
RESIDUAL_RISK_ACCEPTED
```

现有 `DECISION` 中记录：

```text
Residual Risk
Why Non-blocking
Evidence Basis
Accepted By
Affected Scope
Future Action
```

不新增 `risk-register.md`、`waiver-log.md` 或 `contract-change-history.md`。

旧证据不得改写，只能标记有效、失效或需复验。

---

# 16. 人机协作验证

## 16.1 触发场景

Codex 无法独立执行：

- 已登录真实浏览器；
- 用户本机凭据；
- Windows/macOS 特定权限；
- 桌面应用交互；
- 手机或硬件设备；
- 人工视觉判断；
- 用户专属第三方账号；
- 真实本地服务。

## 16.2 HUMAN_VERIFICATION_REQUEST

必须包含：

```text
Verification ID
Related Acceptance Criterion
Candidate SHA
验证目的
前置条件
操作步骤
预期结果
失败表现
需要的证据
脱敏要求
证据有效期
```

## 16.3 HUMAN_VERIFICATION_RESPONSE

必须包含：

```text
Verification ID
Candidate SHA
Environment
Observed Result
Evidence
Unexpected Behavior
Result Claimed：PASS / FAIL
```

Goalkeeper 将有效响应转换为紧凑 `EVIDENCE_RECORD`；只有截图、日志片段或外部结果确有证明价值时，才保存受限附件。

## 16.4 处理边界

- Goalkeeper 核对 ID、SHA、来源并持久化；
- Verifier 判断证据是否足以支持结论；
- 用户一句“试过了，没问题”不能单独构成 `PASS`；
- 人工验证不能静默替代合同要求的自动化测试；
- Candidate 变化后，受影响人工证据失效；
- 人工证据必须说明环境、观察结果与异常；
- Token、Cookie、账号、客户数据等必须脱敏；
- 用户风险接受不能替代当前合同要求的证据。

证据来源：

```text
AGENT_EXECUTED
USER_EXECUTED
EXTERNAL_SYSTEM
```

---

# 17. 项目状态、Pulse 与预测

## 17.1 强制状态更新时间点

- 有意义的工作单元完成；
- 进入验证；
- 验证失败；
- Builder 内部同一失败路径达到修复上限；
- 出现或处理 `EFFICIENCY_EXCEPTION`；
- 生成新的 `CONVERGENCE_SNAPSHOT`；
- Specialist 被请求、批准、补证、解决或未解决；
- 出现阻塞；
- 范围变化；
- 路线变化；
- 关键决定；
- 预测显著变化；
- 里程碑进入 REVIEW、REPAIR、ACCEPTED 或 BLOCKED；
- 会话结束前；
- 工作转交给其他角色或线程。

## 17.2 Project Pulse

```text
Project Pulse

Goal：
Alignment：ON_TRACK / AT_RISK / OFF_TRACK / UNKNOWN
Current Milestone：
State：
Current Revision：
Latest Candidate SHA：
Convergence：IMPROVING / STALLED / REGRESSING / UNKNOWN / NOT_APPLICABLE
Specialist：NONE / ACTIVE / EVIDENCE_NEEDED / RESOLVED / UNRESOLVED / UNAVAILABLE
Done：
Next：
Evidence：
Blockers：
Decision Needed：
Forecast：
Confidence：LOW / MEDIUM / HIGH
```

状态回执保持紧凑，不复制完整 Build、Review、Specialist 或调试历史。

## 17.3 预测规则

不得用：

```text
已完成任务数 ÷ 总任务数
```

至少报告：

```text
已验收里程碑
总已知里程碑
当前里程碑
剩余已知任务
新增未计划工作
关键路径
当前阻塞
剩余有效工作量区间
预计工作轮次
预测置信度
与上次预测的变化
变化原因
```

数据不足时：

```text
Forecast：NOT_READY
Reason：范围尚未稳定或缺少可比较基线
Next Reforecast：指定节点
```

相较上次显著增加时，必须解释新增内容、漏识别原因、范围影响和是否需要用户决定。不得将“节省 Token”作为缩减必要工作或验证的理由。

---

# 18. 默认自治与连续模式

## 18.1 默认模式

```text
PAUSE_AFTER_MILESTONE
```

里程碑 `ACCEPTED` 后：

- 更新 Roadmap、Status、Evidence、Convergence 和 Forecast；
- 逻辑关闭当前 Builder、Verifier 与已完成 Specialist；
- 停止；
- 等待用户批准下一里程碑。

## 18.2 受控连续模式

用户可以预先开启：

```text
CONTINUOUS_MODE
```

仅在全部满足时自动进入下一里程碑：

```text
当前里程碑 ACCEPTED
Alignment Audit PASS
Technical Verification PASS
必需本地验证 PASS 或不适用
下一里程碑已预先批准
路线未变化
范围无未批准扩大
预测无显著异常
无待用户决定
无高风险或不可逆操作
无活动 Specialist
无验收必要的 SPECIALIST_UNRESOLVED / UNAVAILABLE
Convergence 不是 STALLED 或 REGRESSING
```

任一条件不满足即暂停。停止后不得由 Goalkeeper自行恢复连续模式。

---

# 19. 中断恢复

## 19.1 恢复事实源

唯一恢复依据：

```text
Git
Canonical Project Sources
最新 STATUS
持久化 Build / Review / Specialist / Decision / Acceptance Evidence
```

Thread ID 只用于追溯，不是恢复依赖。不得把旧聊天全文、模型推理或临时日志作为唯一恢复来源。

V1 不依赖文件读取缓存、Repo Map、语义索引或长期 Agent Memory。

## 19.2 Control Run 与 Lease Epoch

每次调用或恢复生成：

```text
Control Run ID
Lease Epoch
```

所有新工作单和报告必须携带这两个字段。

## 19.3 恢复动作

### ACTIVE 且无 Candidate

创建新 Builder，从以下最小事实继续：

```text
有效 WORK_ORDER
Base SHA
当前里程碑 Worktree 状态
最近 BUILD_REPORT（如有）
Required Verification
Next Authorized Action
```

不回放旧 Builder 聊天。

### 已有 Candidate、无有效 Review

创建新 Verifier，对同一 Candidate SHA 重新验证。输入只包括 `VERIFY_ORDER`、固定 Diff、有效 Evidence 和必要风险。

### REPAIR

创建新 Builder，读取：

```text
有效 WORK_ORDER
Current Candidate SHA
最近 REVIEW_REPORT
正式 REWORK_ORDER
最新 CONVERGENCE_SNAPSHOT
Required Verification
```

只处理未通过 Finding 和受影响回归。

### Review PASS、验收未持久化

Goalkeeper 核对 Candidate、合同、报告、Specialist 依赖和版本完整性；一致则完成持久化，否则重新验证。

### Specialist ACTIVE / EVIDENCE_NEEDED

恢复后逻辑撤销旧 Specialist Thread，但保留同一个：

```text
Specialist Order ID
Evidence SHA
Evidence Round
Allowed Scope
```

如专业判断仍为必要前提，可创建替代线程继续同一 Order；这属于中断恢复，不视为同一问题的第二次咨询。必须重新创建固定 SHA 的临时 Worktree。

### ACCEPTED

不恢复旧角色，只校准状态并准备下一里程碑。

## 19.4 旧线程

- 恢复后逻辑撤销旧租约；
- 不再接受旧线程新回执；
- 迟到回执标记 `STALE_REPORT_REJECTED`；
- 不依赖 UI 是否存在真正归档按钮；
- 旧 Specialist 报告若基于错误 Epoch、错误 SHA 或已被替代 Order，必须拒绝。

---

# 20. Worktree 与分支清理

## 20.1 Verifier Worktree

满足以下条件可以自动清理：

```text
Review Report 已持久化
Candidate Commit 仍存在
HEAD 与 Candidate 一致
无待调查环境异常
无未登记跟踪文件修改
必要日志已保存
无进程占用
```

仅使用标准：

```text
git worktree remove
```

禁止：

```text
--force
git clean
直接递归删除目录
```

清理失败：

```text
CLEANUP_DEFERRED
```

`REVIEW_INVALID`、`VERSION_INTEGRITY_FAIL`、环境异常时默认保留现场。

## 20.2 Specialist Worktree

最终 `SPECIALIST_REPORT` 已持久化后，满足以下条件可以自动清理：

```text
实际 HEAD = Specialist Evidence SHA
无 staged changes
无 tracked changes
必要 Evidence 已保存
无待调查诊断异常
无进程占用
```

同样只允许标准 `git worktree remove`，禁止 `--force`、`git clean` 或递归强删。

以下情况默认保留现场：

```text
SPECIALIST_REPORT_INVALID
诊断工具修改跟踪文件
版本完整性不明
外部进程仍占用
清理目标无法确认归属
```

清理失败标记：

```text
SPECIALIST_CLEANUP_DEFERRED
```

## 20.3 Builder Worktree

里程碑结束后默认保留，包括：

```text
ACCEPTED
BLOCKED
CHANGED
CANCELLED
```

因为 `ACCEPTED` 不等于已合并。

## 20.4 本地候选分支

永不自动删除。删除前必须单独授权，并确认 Commit 已可靠保留或用户明确永久放弃。

---

# 21. Goal 级最终审计

## 21.1 触发

所有必需里程碑 `ACCEPTED` 后：

```text
Goal State：GOAL_REVIEW
```

Goalkeeper 创建：

```text
Verifier-G<Goal-ID>-Final
```

要求：

- 全新 Agent Thread；
- 全新验证 Worktree；
- 不继承里程碑 Verifier 推理过程；
- 绑定最终 `Goal Code SHA` 与 `Goal Checkpoint SHA`；
- 先验证两者之间只有允许的控制记录差异；
- 不因前序证据有效而跳过 Goal Contract 明确要求的端到端验证。

## 21.2 Goal Alignment Audit

验证：

- 最终目标真正达到；
- 成功标准均有证据；
- 非目标仍被遵守；
- 所有必要里程碑完成；
- 无遗漏、取消或静默缩减需求；
- 所有批准变化进入最新合同；
- 累计实现仍解决最初问题；
- 无阻止结束的未决事项；
- 所有验收必要的 Specialist 问题均已解决或由其他充分证据覆盖。

## 21.3 End-to-End Technical Verification

验证：

- 最终累计版本可构建、可运行；
- 关键端到端流程通过；
- 跨里程碑集成正确；
- 回归测试通过；
- 数据、配置、权限、兼容性满足；
- 本地、浏览器、设备、人工验证完整；
- 控制文档与实现一致；
- 最终版本完整性成立；
- 非阻断残余风险被准确记录而不是伪装为已证明。

Goal 级审计可以复用仍绑定最终版本的有效低风险证据，但必须执行合同明确要求的关键端到端、跨里程碑和高风险复验。效率规则不能成为削弱最终审计的理由。

## 21.4 最终结果

全部通过：

```text
Goal State：GOAL_ACCEPTED
```

失败：

- 局部实现缺陷 → `GOAL_REPAIR`；
- 原合同遗漏 → `CHANGED` 并由用户批准补充里程碑；
- 上游证据失效 → 重新打开受影响里程碑，下游标记 `RECHECK_REQUIRED`；
- 必要专业风险未解决 → `BLOCKED` 或 `HUMAN_VERIFICATION_REQUIRED`。

最终审计不能被连续模式跳过。

---

# 22. Skill 与 Custom Agent 产品结构

## 22.1 固定命名

```text
Repository：codex-project-flight-control
Skill：project-flight-control
Display Name：Project Flight Control
Builder Agent：project_flight_builder
Verifier Agent：project_flight_verifier
Builder TOML：project-flight-builder.toml
Verifier TOML：project-flight-verifier.toml
```

V1 不安装 Specialist Agent TOML。Specialist 在运行时由 Goalkeeper 创建为通用临时 Subagent。

## 22.2 推荐仓库结构

```text
codex-project-flight-control/
├─ README.md
├─ LICENSE
├─ VERSION
├─ CHANGELOG.md
│
├─ skill/
│  └─ project-flight-control/
│     ├─ SKILL.md
│     ├─ agents/
│     │  └─ openai.yaml
│     ├─ references/
│     │  ├─ orchestration-protocol.md
│     │  ├─ roles-and-authority.md
│     │  ├─ modes-and-state-machine.md
│     │  ├─ git-and-worktrees.md
│     │  ├─ evidence-and-recovery.md
│     │  ├─ message-contracts.md
│     │  ├─ builder-debugging.md
│     │  ├─ specialist-protocol.md
│     │  └─ windows-runtime.md
│     └─ assets/
│        └─ templates/
│           ├─ project.md
│           ├─ roadmap.md
│           ├─ status.md
│           ├─ decisions.md
│           ├─ work-order.md
│           ├─ build-report.md
│           ├─ verify-order.md
│           ├─ review-report.md
│           ├─ rework-order.md
│           ├─ evidence-record.md
│           ├─ specialist-request.md
│           ├─ specialist-order.md
│           ├─ specialist-report.md
│           ├─ decision-packet.md
│           ├─ human-verification-request.md
│           ├─ human-verification-response.md
│           ├─ acceptance-report.md
│           └─ final-review-report.md
│
├─ codex-agents/
│  ├─ project-flight-builder.toml
│  └─ project-flight-verifier.toml
│
├─ scripts/
│  ├─ install.ps1
│  ├─ update.ps1
│  ├─ uninstall.ps1
│  └─ doctor.ps1
│
├─ evals/
│  ├─ scenarios/
│  │  ├─ core-governance/
│  │  ├─ builder-efficiency/
│  │  ├─ full-workflow/
│  │  └─ specialist-capability/
│  ├─ expected/
│  └─ run-evals.ps1
│
└─ docs/
   └─ project-flight-control-design.md
```

不创建通用 `token-efficiency.md`。高频效率纪律固化在 Builder TOML；只有失败调试和 Specialist 才按需加载独立 Reference。

## 22.3 渐进式加载

### SKILL.md

只承担：

- 适用边界；
- 显式调用；
- Goalkeeper 身份；
- Preflight；
- START / RESUME / AUDIT / STATUS_ONLY 入口；
- 强制三角色隔离；
- 顶层状态流；
- 按阶段加载 Reference；
- Specialist 请求与门禁入口；
- 强制暂停条件；
- 固定回执。

`SKILL.md` 不重复 Builder 详细效率规则、Verifier 详细验证规则、调试步骤或 Specialist 全部字段。

### 运行时提示预算目标

提示预算按实际 Token 估算，而不是按文件行数判断。V1 的设计目标：

```text
核心 SKILL.md：约 1,000–1,500 tokens
Builder TOML：约 800–1,200 tokens
Verifier TOML：约 500–800 tokens
builder-debugging.md：约 500–800 tokens，仅失败时加载
specialist-protocol.md：约 300–500 tokens，仅获批时加载
```

这些是实现与评估阶段的控制目标，不是已经验证的最优值。任一核心文件明显超过目标时，必须先去重、拆分或证明无法通过更小的渐进加载结构表达；不得仅因“规则更完整”持续扩张常驻上下文。

### Builder Agent TOML

只固化每次实现都必须遵守的高频规则：

```text
Start From Evidence
Targeted Context
Reuse Before Create
Minimal Diff
Incremental Verification
Delta Rework
Accurate Reporting
```

测试、构建或行为异常时才加载 `builder-debugging.md`。

### Verifier Agent TOML

固化：

```text
Alignment Audit
Evidence Integrity
最小独立复验
风险触发扩大
不可修改 Candidate
```

Verifier 不加载 Builder 的完整效率协议。

### specialist-protocol.md

只有 `SPECIALIST_REQUEST` 获批时加载，并与 `SPECIALIST_ORDER` 一起注入临时 Subagent。

### assets/templates/

只定义准确输出结构，不重复解释流程。

### scripts/

仅用于需要确定性的安装、升级、卸载和诊断，不把判断型治理逻辑、上下文路由或 Token 优化全部脚本化。

## 22.4 单一权威定义位置

每条强制规则只有一个权威定义位置：

- 状态转换 → `modes-and-state-machine.md`；
- Git、Worktree 与写入租约 → `git-and-worktrees.md`；
- Evidence、收敛与恢复 → `evidence-and-recovery.md`；
- 消息字段 → `message-contracts.md` 与模板；
- Builder 高频效率纪律 → `project-flight-builder.toml`；
- Builder 失败调试 → `builder-debugging.md`；
- Verifier 固有验证边界 → `project-flight-verifier.toml`；
- Specialist 边界与运行协议 → `specialist-protocol.md`；
- SKILL.md 只引用，不复制完整细节。

---

# 23. Codex 配置与启动门禁

## 23.1 个人级安装路径

```text
Skill：$HOME/.agents/skills/project-flight-control/
Builder：~/.codex/agents/project-flight-builder.toml
Verifier：~/.codex/agents/project-flight-verifier.toml
```

不安装固定 Specialist 配置。

## 23.2 Custom Agent 配置策略

两个正式 Agent TOML：

- 必须包含 `name`、`description`、`developer_instructions`；
- 不硬编码具体模型；
- 未显式配置时继承父线程模型与推理强度；
- Skill 可按任务清晰度与风险请求 `low / medium / high / xhigh` 中当前模型支持的级别；
- `medium` 作为多数清晰任务的平衡起点；
- `high` 仅用于复杂逻辑、边界或高风险审查；
- `xhigh` 仅用于确有必要且模型支持的极高难度判断；
- 不为所有 Builder 与 Verifier 固定请求 `high`，因为更高推理强度会增加时间和 Token 使用；
- 不支持请求级别时必须如实记录实际能力，不得伪造；
- Builder TOML 固化核心效率纪律；
- Verifier TOML 固化独立验证和证据边界；
- Verifier 需要可运行验证的工作区权限，但仍受角色规则和 Git 完整性门禁约束。

## 23.3 SUBAGENT_PREFLIGHT

Skill 开始前必须检查：

```text
Multi-Agent Enabled
Builder Profile Found
Verifier Profile Found
Profile Compatibility
Thread Capacity
Parent Model
Requested / Effective Reasoning Effort
Current Permission Mode
Git Repository
Base Commit
Worktree Capability
Control File Mapping
```

结果：

```text
PASS / BLOCKED
```

任一正式三角色必需项不满足时：

- 不得在主线程模拟角色；
- 不得改用通用 Agent 代替正式 Builder / Verifier；
- 不得省略 Verifier；
- 不得开始正式实施。

## 23.4 Specialist 能力与核心发布边界

Runtime Specialist 是 V1 已定义协议、但受客户端能力门禁控制的条件增强，不是三角色核心发布依赖。

三角色核心包括：

```text
Goalkeeper + Builder + Verifier
Git / Worktree / Candidate SHA
Builder Efficiency Protocol
独立验证、返工、收敛与恢复
```

核心 V1 可以在 Specialist 为 `UNKNOWN` 或 `UNAVAILABLE` 时发布，但必须同时满足：

```text
三角色核心发布门禁全部 PASS
Specialist 状态被准确报告
文档与回执未声称 Specialist 已可用
需要 Specialist 的任务会 BLOCKED 或改用充分的替代证据
Goalkeeper 不在主线程模拟 Specialist
```

只有存在仍然有效的主动验证记录时，发布说明和运行回执才能标记：

```text
SPECIALIST_CAPABILITY：AVAILABLE
```

## 23.5 Specialist 能力状态模型

统一状态：

```text
AVAILABLE
UNKNOWN
UNAVAILABLE
```

语义：

```text
AVAILABLE
= 显式 Smoke Test 或一次真实 Specialist 调用完整成功，且验证记录仍匹配当前环境。

UNKNOWN
= 前置条件看起来具备，但尚未主动验证；或原 AVAILABLE 记录因环境变化、失败而失效。

UNAVAILABLE
= 当前环境明确缺少创建临时 Subagent、固定 SHA Worktree、只读边界、结构化回执或安全清理中的必要能力。
```

普通三角色工作不因 `UNKNOWN / UNAVAILABLE` 自动阻塞。只有该专业判断成为安全性、数据完整性或正确性的验收必要前提时，才进入：

```text
SPECIALIST_CAPABILITY：UNAVAILABLE
→ BLOCKED / HUMAN_VERIFICATION_REQUIRED / 请求充分替代证据
```

## 23.6 普通 Doctor：被动检查、零模型调用

默认 `doctor.ps1` 不创建 Subagent，不触发模型调用，也不运行 Specialist Smoke Test。它只被动检查：

```text
Skill 与两个正式 Agent 配置状态
当前 Codex 客户端暴露的 Subagent 能力
Git 与 Disposable Worktree 前置条件
可建立只读权限边界的配置条件
临时目录与安全清理条件
最近一次 Specialist 主动验证记录
该记录与当前环境指纹是否一致
```

状态映射：

```text
必要前置条件明确缺失
→ UNAVAILABLE

前置条件存在，但从未主动验证或记录已失效
→ UNKNOWN

存在仍然有效的主动验证记录
→ AVAILABLE
```

普通安装、升级和默认 Doctor 不得为了确认 Specialist 而静默消耗模型额度。

## 23.7 显式 Specialist Smoke Test

建议的 Windows 显式入口：

```powershell
.\scripts\doctor.ps1 -SpecialistSmoke
```

该模式会产生一次受控的 Subagent / 模型调用，必须由用户显式执行。它使用 Skill 自带的一次性微型 Git 仓库验证：

```text
创建一次性 Git 仓库与固定测试 SHA
→ 创建独立 Specialist Worktree
→ 启动通用临时 Subagent
→ 注入最小只读 Specialist Order
→ 读取指定文件并返回结构化 SPECIALIST_REPORT
→ 验证实际 SHA、只读边界和报告字段
→ 验证无 staged / tracked changes
→ 关闭线程
→ 使用标准 git worktree remove 安全清理
```

Smoke Test 只证明基础运行能力，不证明真实安全、数据库、并发或性能问题已经得到专业验证。

一次真实 Specialist 调用若完整满足相同的不变量，也可以建立 `AVAILABLE` 记录。

## 23.8 能力验证记录与失效

验证记录保存在本机 Project Flight Control 状态中，不写入业务仓库。优先复用 `install-state.json`，至少记录：

```text
Specialist Capability Status
Verified At
Verification Source：SMOKE_TEST / REAL_INVOCATION
Codex Client Version
Skill Major Version
Subagent / Agent Runtime Config Fingerprint
Permission / Sandbox Fingerprint
Worktree Capability Result
Structured Report Result
Cleanup Result
Invalidation Reason
```

以下任一变化使持久化状态从 `AVAILABLE` 回到 `UNKNOWN`：

```text
Codex 客户端版本变化
Skill 主版本变化
Subagent 或 Agent 配置变化
权限、审批或沙箱配置变化
上次 Specialist 调用发生隔离、SHA、回执或清理失败
验证记录缺失、损坏或无法确认来源
```

明确缺少必要能力时可进一步标记 `UNAVAILABLE`。

## 23.9 实际调用前轻量复核

Goalkeeper 在每次已批准 Specialist 调用前都必须处理当前能力状态：

```text
持久化状态 = UNAVAILABLE
→ 不创建 Specialist；按当前任务是否依赖它继续或 BLOCKED。

持久化状态 = UNKNOWN / AVAILABLE
→ 执行轻量复核，并尝试当前真实调用。
```

轻量复核至少确认：

```text
当前客户端能力仍存在
独立 Worktree 创建成功
实际 HEAD = Evidence SHA
当前只读边界可确认
临时线程成功启动
结构化 Order 可投递
```

不重复完整 Smoke Test。结果处理：

```text
真实调用完整成功并满足全部不变量
→ 本次调用有效
→ 可以建立或刷新 AVAILABLE 记录

复核或真实调用失败
→ 本次调用：UNAVAILABLE
→ 原 AVAILABLE 记录失效为 UNKNOWN；若确认能力缺失则标记 UNAVAILABLE
→ 记录失败原因
→ 按当前任务是否依赖 Specialist 继续或 BLOCKED
```

## 23.10 权限现实边界

Subagent 的有效权限受到父线程实时权限、沙箱和运行时覆盖影响。必须检查实际能力，而不是只相信 TOML 默认值。

- Subagent 可能继承父线程当前 permission mode；
- 自定义 Agent 可以声明更窄沙箱，但不能假定能突破父线程限制；
- Specialist 默认只读、无网络；
- Verifier 与 Specialist 允许的临时写入不得改变跟踪文件；
- 选择满足任务所需的最窄权限配置。

Git Commit 因 `.git` 保护或审批策略无法执行时：

```text
BLOCKED_BY_PERMISSION
```

不得编造 Candidate SHA。

---

# 24. Windows V1 安装、升级与卸载

## 24.1 工具

```text
install.ps1
update.ps1
uninstall.ps1
doctor.ps1
```

不自动安装或升级 Codex、Git、PowerShell。

## 24.2 安装状态目录

```text
%LOCALAPPDATA%\ProjectFlightControl\
├─ install-state.json            # 安装清单 + Specialist 能力验证记录
├─ staging\
└─ backups\
   └─ <timestamp>-<version>\
```

备份不得放入 Skills 扫描目录。

## 24.3 事务式安装语义

“事务式”表示逻辑可恢复：

```text
VALIDATE_SOURCE
→ INSPECT_TARGETS
→ STAGE_FILES
→ VERIFY_STAGED_HASHES
→ INSTALL
→ WRITE_MANIFEST
→ RUN_DOCTOR（被动检查，不触发 Specialist 模型调用）
→ PASS
```

不宣称 Windows 多文件操作具有绝对原子性。

## 24.4 目标文件状态

```text
ABSENT
MANAGED_UNCHANGED
MANAGED_MODIFIED
UNMANAGED_CONFLICT
```

- `MANAGED_MODIFIED`：暂停，不覆盖用户修改；
- `UNMANAGED_CONFLICT`：暂停，不覆盖、不删除、不自动改名。

## 24.5 install-state.json

至少记录：

```text
Product
Version
Installed At
Source Version / Commit
Managed Files
Destination Paths
SHA-256
Backup Reference
Installer Version
Last Doctor Result
Specialist Capability Record
```

## 24.6 升级

- 校验旧清单；
- 检查本地修改；
- 创建时间戳备份；
- 暂存并校验新版本；
- 替换；
- 运行 Doctor；
- 失败时恢复备份并校验。

回滚也失败：

```text
PARTIAL
MANUAL_RECOVERY_REQUIRED
```

## 24.7 卸载

只删除清单中登记且哈希仍匹配的文件。

- 用户修改过的文件保留；
- 含未知文件的目录保留；
- 不删除项目仓库内控制文件、证据、分支或 Worktree；
- 不使用递归强制删除未知内容；
- 备份 V1 默认保留。

## 24.8 Doctor 与 Specialist Smoke 的安装边界

默认安装、升级和回滚只运行被动 Doctor：

```text
无 Subagent 创建
无模型调用
无 Specialist Smoke Test
```

显式 `-SpecialistSmoke`：

- 不属于普通安装成功的必要条件；
- 不得由安装器静默追加；
- 成功后可以把 Specialist Capability 记录为 `AVAILABLE`；
- 失败不撤销已经通过的三角色核心安装，但必须准确记录 `UNKNOWN / UNAVAILABLE`；
- 若安装包、文档或发布说明声称 Specialist 为 `AVAILABLE`，则对应客户端与环境的有效主动验证记录必须存在。

---

# 25. 强制暂停条件

出现任一情况，不得继续扩大实现：

- 最终目标或验收标准不清楚；
- 当前实现与路线图重大冲突；
- 需要实质目标或范围变化；
- 需要重大架构变化；
- 数据模型或迁移变化；
- 安全、权限、认证、凭据或隐私边界变化；
- 引入付费服务或重大生产依赖；
- 必需验证无法执行；
- 本地与远程结果冲突；
- 剩余工作显著增加；
- Builder 对同一失败路径完成两次证据驱动修复后仍不收敛；
- 同一核心失败跨两个 Revision 持续存在；
- 连续两轮没有新增通过的验收项或 Finding 严重度没有下降；
- 当前里程碑无法带来预期结果；
- 下一里程碑不再是正确目标；
- 版本完整性失效；
- Subagent 配置、线程容量、权限或 Worktree 门禁失败；
- 验收必要的 Specialist 能力不可用；
- 一次补证后验收必要的 Specialist 问题仍为 `UNRESOLVED`；
- Specialist 实际检查的 SHA、权限或 Worktree 完整性无法确认；
- `EFFICIENCY_EXCEPTION` 显示完成任务必须修改合同明确排除的范围；
- 继续推进需要删除测试、降低断言或弱化必要验证。

暂停后输出：

```text
Decision Packet

发生了什么
为什么不能安全继续
相关合同版本与 SHA
对目标的影响
对范围的影响
对验证的影响
对剩余工作的影响
可选方案
推荐方案
需要用户决定
```

不得以“节省 Token”作为忽略暂停条件或降低证据标准的理由。

---

# 26. 固定结束回执

```text
Project Control Report

Mode：
Overall Result：PASS / FAIL / PARTIAL / NOT_RUN
Control Run ID：
Lease Epoch：
Goal：
Goal Version：
Goal Alignment：
Goal State：
Current Milestone：
Milestone Contract Version：
Milestone State：

Completed：
Changed：
Evidence：
Verification：
Scope Change：
Roadmap Change：
Efficiency Exception：NONE / RECORDED / CONTRACT_CHANGE_REQUIRED
Convergence：IMPROVING / STALLED / REGRESSING / UNKNOWN / NOT_APPLICABLE
Specialist Capability：AVAILABLE / UNKNOWN / UNAVAILABLE
Specialist Task：NONE / ACTIVE / EVIDENCE_NEEDED / RESOLVED / UNRESOLVED
Specialist Order / Report：
Blockers：
Residual Risks：
Pending Decisions：
Next Recommended Action：

Accepted Milestones：
Remaining Known Milestones：
Remaining Work Forecast：
Forecast Confidence：
Base SHA：
Latest Candidate SHA：
Goal Code SHA：
Goal Checkpoint SHA：
Last Accepted Checkpoint SHA：
Project Control Files Updated：
Builder Thread：
Verifier Thread：
Specialist Thread：
Builder Worktree：
Verifier Worktree：
Specialist Worktree：
Cleanup Result：
```

不适用字段使用 `NOT_APPLICABLE`，未知字段使用 `UNKNOWN`，未执行验证使用 `NOT_RUN`。回执不复制完整日志、完整聊天或完整内部推理。

未成功执行验证时，不得声称：

- 已通过；
- 已完成；
- 无回归；
- 可以安全进入下一阶段；
- 可以安全发布；
- 已经减少 Token；
- 已经达到某个节省比例。

---

# 27. 分层 RED–GREEN 行为与效率评估

## 27.1 总原则

Skill 必须使用“先观察无 Skill 或无效率协议的基线，再验证规则是否改变行为”的方法开发和验收。

```text
RED：对照场景，记录自然行为、失败与合理化
GREEN：同一场景加载目标规则，验证行为改变
REFACTOR：修正规则并用相同场景复测
```

所有评估必须预先固定：

```text
测试仓库与 Base SHA
任务合同或 WORK_ORDER
验收标准
模型
推理强度
权限与环境
可比较的运行入口
```

不得在看到结果后修改主要指标或成功标准。

## 27.2 第一层：静态包检查

`run-evals.ps1` 自动检查：

```text
Skill 目录结构
SKILL.md Frontmatter
agents/openai.yaml
allow_implicit_invocation = false
两个正式 Custom Agent 名称与配置
不存在固定 Specialist Agent 配置
Builder TOML 包含核心效率纪律
Verifier TOML 包含独立验证边界
builder-debugging.md 与 specialist-protocol.md 按需引用
模板必填字段
Reference 引用断链
PowerShell 语法
危险 Git 命令
硬编码盘符
版本号一致性
安装清单 Schema
不包含未批准的 Runtime Token Telemetry
普通 Doctor 不创建 Subagent、不触发模型调用
Specialist 状态模型与主动验证记录 Schema
Prompt Budget Report 已生成且核心文件未无理由超出目标
```

静态通过不等于行为通过。

## 27.3 第二层：Builder 效率协议 RED–GREEN 对照

使用相同仓库、Base SHA、WORK_ORDER、模型、推理强度和权限分别执行：

```text
RED
→ Builder 不加载执行效率协议

GREEN
→ Builder 加载 project-flight-builder.toml 中的核心效率协议
```

比较：

```text
实际 Token / Agent Usage（客户端可靠提供时）
模型回合数
工具调用次数
读取文件范围
重复读取次数
搜索范围扩大次数
重复测试或构建次数
代码修改量
重复实现数量
内部修复尝试次数
达到 Candidate 所需时间与回合
最终正确性
```

该层回答：

> Builder 效率协议本身是否减少了可观察的重复工作，同时不降低正确性？

## 27.4 第三层：完整三角色流程对照

比较：

```text
普通 Codex 单 Agent 执行
vs
Project Flight Control 完整闭环
```

Project Flight Control 成本必须计算：

```text
Goalkeeper
+
Builder
+
Verifier
+
实际调用的 Specialist
```

重点衡量：

```text
最终 ACCEPTED 任务总成本
总模型回合
总工具调用
总返工 Revision
首次验收通过率
最终验收通过率
错误完成数量
越界修改数量
漏测数量
中断恢复后的重复工作
独立验收发现的真实问题
最终正确性
```

该层回答：

> 三角色增加的调用成本，是否换来了更少错误完成、无效返工、越界修改，或更可靠的恢复与验收？

若总成本稳定显著增加，且没有可验证的质量、恢复或验收收益，则视为架构问题，不能仅因流程“更规范”而判定成功。

## 27.5 第四层：核心效率行为场景

V1 至少包含以下硬门禁场景：

```text
EFF-01 Targeted Context
从目标实现和相邻测试开始，不无依据先扫描整个仓库。

EFF-02 Reuse Before Create
存在明确可复用能力时，不重复创建等价实现。

EFF-03 Minimal Diff
不增加与 WORK_ORDER 无关的修改、重构、依赖或抽象。

EFF-04 Delta Rework
返工只处理未通过 Finding 及受影响回归，不重新实施已通过内容。

EFF-05 Incremental Verification
从最小有效验证逐级扩大，同时不遗漏合同要求。

EFF-06 Debugging Convergence
同一失败路径最多两次证据驱动修复；不收敛时准确停止。

EFF-07 Structured Recovery
中断后从合同、SHA、报告和状态继续，不重新执行已可靠完成的工作。
```

每个场景必须在运行前声明：

```text
Primary Efficiency Metric
Expected Improvement
Allowed Trade-offs
Forbidden Regression
Required Evidence
Repetition Count
```

示例：

```text
Scenario：EFF-02 Reuse Before Create
Primary Metric：重复实现数量
Expected Improvement：GREEN 识别并复用现有能力
Allowed Trade-off：允许少量定向搜索
Forbidden Regression：不得为了复用修改无关模块
Required Evidence：Diff、搜索记录、目标测试
```

## 27.6 第五层：一次性 Git 仓库集成测试

### 三角色核心 V1 必测场景

```text
SC-01 START 正常闭环
SC-02 RESUME 从 Candidate 后恢复
SC-03 AUDIT 发现 BLOCKER 并返工
SC-04 STATUS_ONLY 无写入
SC-05 原工作区有未提交修改
SC-06 非 Git 项目阻塞
SC-07 Candidate SHA 与报告不匹配
SC-08 验证工具修改跟踪文件
SC-09 旧 Lease Epoch 回执迟到
SC-10 两轮返工后仍不收敛
SC-11 人工验证证据不足
SC-12 Accepted Checkpoint 越界含业务代码
SC-13 受控连续模式安全停止
SC-14 Goal 级最终审计
SC-15 安装、升级、回滚、卸载往返
SC-16 Goalkeeper 合同级侦察不下沉为实现分析
SC-17 Builder 第三层上下文扩展产生 EFFICIENCY_EXCEPTION
SC-18 Verifier 复用有效证据并执行最小独立复验
SC-19 Builder 同一失败路径两次修复后停止
SC-20 紧凑 Evidence + 必要失败附件
SC-24 用户不能把证据缺口豁免为 PASS
SC-27 Company OS、Repo Map、长期 Memory 与 Runtime Telemetry 均未进入 V1
SC-28 普通 Doctor 被动运行且不产生 Specialist 模型调用
SC-31 Specialist UNKNOWN / UNAVAILABLE 不阻断三角色核心发布，但验收必要任务安全阻塞
```

### Runtime Specialist 条件能力场景

只有发布说明准备标记 `SPECIALIST_CAPABILITY：AVAILABLE` 时，以下场景才是硬门禁：

```text
SC-21 Specialist 固定 SHA、独立 Worktree、一次补证后结束
SC-22 Specialist 不直接发布正式 BLOCKED / ACCEPTED
SC-23 Specialist 未解决必要前提阻断验收
SC-25 Candidate 变化后旧 Specialist Evidence 不自动继承
SC-26 Specialist 中断恢复沿用同一 Order，不形成第二次咨询
SC-29 显式 Specialist Smoke 完整成功后才标记 AVAILABLE
SC-30 客户端、Skill 主版本或权限配置变化使 AVAILABLE 失效为 UNKNOWN
```

当能力为 `UNKNOWN / UNAVAILABLE` 时，这组场景标记 `NOT_APPLICABLE`，不得据此声称 Runtime Specialist 已经可用；其结果不阻断三角色核心 V1 发布。

每个场景保存：

```text
Initial State
Prompt
Control Variables
Expected Actions
Forbidden Actions
Expected Files
Expected Git Graph
Expected Status
Primary Efficiency Metric
Expected Improvement
Allowed Trade-offs
Forbidden Regression
Actual Evidence
Token Usage / NOT_AVAILABLE
Verdict
```

行为存在模型波动时，关键提示遵循类场景至少运行 5 次独立新上下文；高成本端到端场景的重复次数由评估定义预先固定，不得事后挑选最好结果。

## 27.7 统一质量底线与 Token 数据边界

所有 GREEN 场景共同满足：

```text
最终正确性不得低于 RED
不得新增安全、数据、权限或兼容性风险
不得增加越界修改
不得通过减少必要验证制造效率提升
不得隐藏 FAIL / PARTIAL / NOT_RUN
不得删除测试、降低断言或放宽验收标准
不得出现无限调试、正式返工或 Specialist 调用
```

Token 数据处理：

```text
客户端提供可靠、可归属数据
→ 如实记录和比较

客户端不提供或归属不可靠
→ TOKEN_USAGE：NOT_AVAILABLE
→ 使用可观察代理指标
```

代理指标只能证明重复工作行为变化，不能换算成未经验证的 Token 节省百分比。

正式运行时不建设：

```text
Token 数据库
文件访问监控器
后台遥测
长期行为追踪
```

## 27.8 分层 V1 发布门禁

### 第一层：质量与安全硬门禁

任一项失败即阻断发布：

```text
最终正确性下降
新增安全、数据、权限或兼容性风险
必要验证被跳过
Candidate 与 Evidence 版本不一致
越界修改增加
正式角色隔离失效
无限调试、返工或 Specialist 调用
用户风险接受被错误转换为 PASS
```

结果：

```text
QUALITY_AND_SAFETY_GATE：FAIL
```

### 第二层：核心效率行为硬门禁

```text
EFF-01 至 EFF-07：全部 PASS
```

任一核心场景未达到预先定义目标：

```text
CORE_EFFICIENCY_GATE：FAIL
```

### 第三层：量化效果证据

记录但暂不设置统一百分比：

```text
Token / Agent Usage
工具调用数量
读取范围
重复读取次数
测试与构建次数
总执行时间
Revision 数量
首次验收通过率
最终 ACCEPTED 成本
```

数据不可用时标记 `NOT_AVAILABLE`；结果未显示改善时不得宣传 Token 节省。若 GREEN 总成本稳定显著增加且没有可靠性、验收或恢复收益，则升级为架构问题并阻断发布。

### 第四层：Runtime Specialist 条件能力门禁

Runtime Specialist 与三角色核心 V1 分开判定：

```text
Published Specialist Capability = AVAILABLE
→ 存在仍有效的显式 Smoke Test 或等价真实成功调用记录
→ SC-21 / 22 / 23 / 25 / 26 / 29 / 30 全部 PASS
→ Specialist Conditional Scenarios：PASS

Published Specialist Capability = UNKNOWN / UNAVAILABLE
→ Specialist Conditional Scenarios：NOT_APPLICABLE
→ 不阻断三角色核心 V1 发布
→ 不得宣传 Runtime Specialist 已可用
```

若条件能力场景失败，必须停止 `AVAILABLE` 声明并把能力状态更新为 `UNKNOWN / UNAVAILABLE`。只要三角色核心门禁仍全部通过，不因此把已经合格的核心 V1 判定为失败。

最终可安装的**三角色核心 V1**必须满足：

```text
Static Package Checks：PASS
Agent Profile Validation：PASS
Installer Round Trip：PASS
Doctor：PASS
Required RED Baselines：RECORDED
Quality and Safety Gate：PASS
Core Efficiency Gate：PASS
Required Core GREEN Scenarios：PASS
Git / Worktree Integration：PASS
Role Isolation：PASS
Explicit-Only Invocation：PASS
Windows Real-Machine Smoke Test：PASS
Specialist Capability Handling：PASS
Published Specialist Capability：AVAILABLE / UNKNOWN / UNAVAILABLE
Specialist Active Smoke：PASS / NOT_RUN / NOT_SUPPORTED
Specialist Conditional Scenarios：PASS / NOT_APPLICABLE
Open BLOCKER：0
Open MAJOR：0
Known MINOR：已记录
Quantitative Evidence：RECORDED / NOT_AVAILABLE
```

门禁解释：

```text
Published Specialist Capability = AVAILABLE
→ Specialist Active Smoke 必须 PASS，或存在等价的真实成功调用记录；Specialist Conditional Scenarios 必须 PASS。

Published Specialist Capability = UNKNOWN / UNAVAILABLE
→ 不阻断三角色核心发布；Specialist Conditional Scenarios 为 NOT_APPLICABLE；不得宣传 Specialist 已可用；Specialist Capability Handling 必须 PASS。
```

结果只允许：

```text
PASS
FAIL
PARTIAL
NOT_RUN
```

---

# 28. Skill 自身验收标准

## AC-SKILL-001 显式触发

- 未显式调用时不自动启用；
- `$project-flight-control` 可以启用。

## AC-SKILL-002 真实角色隔离

- Goalkeeper 主线程不修改业务代码；
- Builder 和 Verifier 是不同的真实 Subagent Thread；
- 缺失正式 Custom Agent 时流程阻塞；
- Specialist 不被安装或提升为第四个正式角色。

## AC-SKILL-003 阶段式创建

- ACTIVE 后才创建 Builder；
- Candidate 冻结后才创建 Verifier；
- 下一里程碑创建新正式线程；
- Specialist 只有获批 Order 后才临时创建。

## AC-SKILL-004 Git 与 Worktree

- 非 Git 实施阻塞；
- 原工作区保持不变；
- Builder 使用里程碑 Worktree；
- Verifier 使用固定 SHA 的独立 Worktree；
- Specialist 使用独立、固定 SHA、可丢弃 Worktree。

## AC-SKILL-005 证据版本绑定

- 所有报告带 Goal、Milestone、Epoch、Revision 和对应 SHA；
- 旧或错配报告被拒绝；
- Candidate 与 Accepted Checkpoint 被准确区分；
- Specialist Evidence 不自动继承到新 Candidate。

## AC-SKILL-006 单一事实写入者

- Goalkeeper 是控制文件唯一写入者；
- Builder、Verifier、Specialist 不修改控制文件；
- 现有等价文件被复用，不建立重复事实源；
- 不创建 Discovery、Convergence、Risk、Token 等第二套状态文件。

## AC-SKILL-007 独立验证

- Verifier 先做 Alignment Audit 和 Evidence Integrity，再做 Technical Verification；
- 有效 Builder Evidence 可以复用，但至少执行最小独立复验；
- 风险或证据缺口会触发扩大验证；
- 版本完整性失败时不得 PASS。

## AC-SKILL-008 Finding 约束力

- BLOCKER / MAJOR 绑定证据；
- 有效阻断不能被 Goalkeeper 直接忽略；
- MINOR 不阻断且不得触发顺手扩展；
- “不够省 Token”不能单独成为阻断 Finding。

## AC-SKILL-009 返工与调试收敛

- Builder 同一失败路径最多两次证据驱动修复；
- 默认最多两轮正式自动返工；
- 每轮保存最小收敛快照；
- 跨 Revision 提前停止条件生效；
- 不允许无限自动返工。

## AC-SKILL-010 合同变更

- 运行级调整可自治；
- 实质变化必须用户批准；
- 新合同版本触发重新审计和受影响验证；
- 风险接受不能把未证明事实变为 PASS。

## AC-SKILL-011 人机验证

- Codex 无法执行时生成结构化请求；
- 人工结果绑定 Candidate；
- Verifier 审核证据；
- 口头确认不直接 PASS；
- 必要附件受限且脱敏。

## AC-SKILL-012 中断恢复

- 恢复不依赖旧聊天；
- 新 Control Run ID 与 Lease Epoch 生效；
- 旧线程迟到回执被拒绝；
- Builder 从合同、SHA 和最近报告做差量恢复；
- Specialist 中断后沿用同一 Order 恢复。

## AC-SKILL-013 里程碑继承

- 下一里程碑从上一 Accepted Checkpoint 开始；
- 未验收 Candidate 不得成为后继基线。

## AC-SKILL-014 Goal 最终审计

- 所有里程碑通过后仍进入 GOAL_REVIEW；
- 使用全新 Verifier 和 Worktree；
- 必要端到端和高风险验证不得因证据复用被跳过；
- 通过后才允许 GOAL_ACCEPTED。

## AC-SKILL-015 安装安全

- 全局安装可检测冲突；
- 用户修改不被静默覆盖；
- 升级失败可回滚；
- 卸载不删除未知或已修改文件；
- 正式安装只有 Builder 与 Verifier 两个 Custom Agent。

## AC-SKILL-016 真实验证声明

- 未运行检查标记 NOT_RUN；
- 部分执行标记 PARTIAL；
- 不得通过文档审阅替代运行证据；
- 不得声称未测得的 Token 节省比例。

## AC-SKILL-017 Builder 执行效率

- 每个 Builder 自动加载核心效率纪律；
- 从目标证据开始，按三层规则扩大上下文；
- 存在重复概率时先检查复用；
- 默认产生最小 Diff；
- 返工只处理未通过项和受影响回归；
- 偏离最小路径时才输出 `EFFICIENCY_EXCEPTION`。

## AC-SKILL-018 最小角色上下文

- Goalkeeper 只做合同级侦察；
- Builder 不重新分析已经锁定的需求；
- Verifier 不接收 Builder 完整聊天与推理；
- Specialist 只接收窄范围 Context Packet；
- Milestone Contract 是唯一 Execution Contract。

## AC-SKILL-019 增量验证与 Evidence

- Milestone Contract 定义必须证明什么；
- Builder 选择最小有效命令并保存退出码；
- Verifier独立判断证据充分性；
- 成功路径默认只保存紧凑 Evidence；
- 失败或高风险附件有限、相关且脱敏。

## AC-SKILL-020 Specialist 受控扩展

- Specialist 是条件增强，不是三角色核心发布依赖；
- 能力状态为 `UNAVAILABLE` 时不得创建；状态为 `UNKNOWN / AVAILABLE` 时必须先完成调用前轻量复核；
- 从 `UNKNOWN` 发起的真实调用只有在完整成功并满足全部不变量后，才可建立 `AVAILABLE` 记录；
- 同一时间最多一个活动 Specialist；
- 一个 Order 只处理一个问题；
- 最多一次证据补充；
- 默认静态分析，诊断命令最小且与问题绑定；
- Specialist 不修改 Candidate、不创建 Commit、不直接裁决；
- 必要问题未解决时不得验收。

## AC-SKILL-021 效率评估与发布门禁

- Builder 协议与完整三角色流程分别做对照；
- EFF-01 至 EFF-07 全部通过；
- 正确性、安全和必要验证不因效率目标下降；
- Token 不可测时标记 NOT_AVAILABLE；
- 质量、安全与核心效率行为是硬门禁；
- 量化 Token 结果暂不采用武断统一百分比。

## AC-SKILL-022 轻量 V1 边界

- 不安装固定 Specialist Agent；
- 不引入 Repo Map、语义索引、长期 Memory 或读取缓存；
- 不建立 Runtime Token Telemetry；
- 不引入 Company OS 集成；
- 不提供 FAST / STANDARD / DEEP 复杂度模式；
- 核心 Skill 与角色提示采用可审计的 Token 预算目标和渐进加载。

## AC-SKILL-023 Specialist 能力检测与发布语义

- 普通 Doctor 只做被动检查，不创建 Subagent、不触发模型调用；
- 未主动验证但前置条件具备时为 UNKNOWN；
- 前置条件明确缺失时为 UNAVAILABLE；
- 只有显式 Smoke Test 或等价真实调用完整成功时才为 AVAILABLE；
- 客户端、Skill 主版本、Agent 配置或权限环境变化会使 AVAILABLE 失效；
- 实际调用前执行轻量复核，不重复完整 Smoke Test；
- Specialist UNKNOWN / UNAVAILABLE 不阻断三角色核心发布；
- 声称 AVAILABLE 时必须有仍有效的主动验证记录，且对应 Specialist 条件能力场景全部通过；
- 验收必要的 Specialist 不可用时，当前任务不得被错误标记为 PASS。

---

# 29. 当前平台依据与实现注意事项

截至 2026-09-03，已重新核对的官方 Codex 文档支持以下设计依据：

- Skill 使用渐进式披露：初始仅暴露名称、描述和路径，选中后读取完整 `SKILL.md`；因此入口文件仍需保持聚焦；
- Skill 目录以 `SKILL.md` 为必需入口，可以附带 `scripts/`、`references/`、`assets/` 和 `agents/openai.yaml`；
- Codex CLI 或 IDE 可以通过 `$skill` 显式调用；
- `agents/openai.yaml` 的 `policy.allow_implicit_invocation: false` 可以关闭隐式调用，同时保留显式调用；
- 个人 Skill 可放在 `$HOME/.agents/skills`；
- 个人 Custom Agent 可放在 `~/.codex/agents/`，项目级 Agent 可放在 `.codex/agents/`；
- Custom Agent 必需字段为 `name`、`description`、`developer_instructions`；
- 未配置子智能体模型或推理强度时，Subagent 可继承父线程设置；更高 reasoning effort 会增加响应时间和 Token 使用，因此 V1 按风险选择而不是全局固定 high；
- Codex 可以编排创建、路由、等待、继续和关闭 Subagent Thread；
- Subagent 的实际权限会继承或受到父线程当前沙箱、审批和实时覆盖影响；
- Worktree 只适用于 Git 仓库，可提供独立文件副本并共享 Git 元数据；Codex 管理的 Worktree 通常从指定起点创建并默认处于 detached HEAD；
- 权限配置应选择满足任务所需的最窄范围；工作区内 `.git`、`.codex` 等路径可能继续受到保护，因此不能假定 Commit 必然无需批准；
- 官方文档确认 Codex 支持 Subagent、Custom Agent、只读沙箱与 Git Worktree，但这些文档本身不能证明“不安装固定 Specialist TOML、运行时注入窄协议、绑定固定 SHA、受控清理”的完整组合在当前客户端一定可用，因此该组合继续由 D-067 至 D-069 的能力状态、Smoke Test 与实机门禁控制。

实现阶段必须重新核对当时生效的官方文档和实际安装版本。Custom Agent 格式、模型名称、reasoning effort、权限、UI 和 Worktree 管理方式都可能变化；V1 应把这些当成适配层与实机门禁，而不是永久不变的协议事实。

官方参考：

- https://developers.openai.com/codex/build-skills
- https://developers.openai.com/codex/agent-configuration/subagents
- https://developers.openai.com/codex/environments/git-worktrees
- https://developers.openai.com/codex/config-reference
- https://developers.openai.com/codex/permissions

---

# 30. 规格自审结果

## 30.1 Placeholder 检查

- 未发现未决占位标记；
- 具体脚本实现与命令适配留待实现计划，不构成第二套设计；
- D-032 至 D-069 已分别进入权威章节，不以问答附录代替正式规则。

## 30.2 一致性检查

已统一以下容易冲突的概念：

- 主线程 = Goalkeeper；
- 固定正式角色只有 Goalkeeper、Builder、Verifier；
- Specialist 是一次性咨询线程，不是第四个正式角色，也不是三角色核心发布依赖；
- 独立 Thread 与独立 Worktree 是不同隔离层；
- Verifier / Specialist 不修改 Candidate，不等于禁止所有临时文件；
- Candidate SHA 与 Accepted Checkpoint SHA 分离；
- 下一里程碑继承 Checkpoint，而不是未带治理记录的 Candidate；
- ACCEPTED 不等于 Merge、Push、发布或部署；
- Goalkeeper 有最终流程决策权，但无权改写有效技术证据；
- 人工验证是结构化证据来源，不是口头豁免；
- 风险接受不等于事实已被证明；
- Milestone Contract 是唯一 Execution Contract；
- Goalkeeper 合同级侦察不等于 Architect 或 Builder 实现分析；
- Builder 是唯一加载完整执行效率纪律的正式角色；
- Verifier 复用证据不等于继承 Builder 结论；
- `EFFICIENCY_EXCEPTION` 不等于阻断 Finding；
- 旧 Specialist Evidence 不自动证明新 Candidate；
- Token 优化目标不能削弱正确性、安全或必要验证；
- Specialist 的 `AVAILABLE / UNKNOWN / UNAVAILABLE` 是能力证据状态，不是任务验收状态；
- 普通 Doctor 的零模型调用与显式 Smoke Test 的主动验证职责已经分离；
- Specialist 不可用可以限制特定高风险任务，但不能伪装成三角色核心安装失败。

## 30.3 范围检查

V1 范围聚焦于：

```text
Codex
Windows
个人级全局安装
三角色开发闭环
Builder 执行效率纪律
受控临时 Specialist（条件能力）
Git / Worktree / Compact Evidence
离线 RED–GREEN 效率评估
```

明确排除：

```text
Company OS
更多固定角色
任务复杂度模式
Repo Map / 语义索引 / 长期 Memory / 读取缓存
Runtime Token Telemetry
其他智能体平台与正式跨平台承诺
```

## 30.4 尚待实现阶段验证的风险

1. Codex 当前具体客户端是否能按预期把两个正式 Custom Agent 显示为可检查子线程；
2. Skill 是否能稳定按阶段创建、等待、继续和关闭正式与临时线程；
3. 父线程权限覆盖对 Builder、Verifier、Specialist 实际权限的影响；
4. Windows 原生沙箱下 Git Worktree、detached HEAD 与 Commit 审批行为；
5. 子线程能否稳定接收指定工作目录和固定 Candidate / Evidence SHA；
6. 受限可写 Verifier 与默认只读 Specialist 对不同项目工具的兼容性；
7. 临时 Specialist 是否能在不安装固定 TOML 的前提下稳定获得窄范围协议；
8. 长流程中结构化回执、Evidence Round 和跨 Revision 收敛是否持续遵循；
9. Builder 两次内部修复上限是否能减少盲修，而不造成过多不必要交接；
10. Verifier 的证据复用与最小独立复验是否能兼顾效率和独立性；
11. EFF-01 至 EFF-07 的 RED–GREEN 结果是否稳定；
12. Codex 客户端能否提供可靠且可归属的 Token / Agent Usage；
13. 完整三角色流程的总体成本是否得到足够的可靠性、恢复或验收收益补偿；
14. 普通 Doctor 能否稳定做到被动检查且零 Specialist 模型调用；
15. 显式 Smoke Test 能否在一次性仓库中验证运行时临时 Specialist 的固定 SHA、只读、结构化回执与安全清理；
16. Specialist 验证记录的环境指纹与失效规则是否能准确避免过期 AVAILABLE 声明；
17. Specialist UNKNOWN / UNAVAILABLE 时，三角色核心发布与高风险任务阻塞语义是否都能正确执行。

这些风险必须通过一次性仓库、真实 Codex 客户端和 Windows 实机评估验证，当前状态均为 `NOT_RUN`。

---

# 31. 规格批准后的下一阶段

本次 D-032 至 D-069 已直接收敛进主规格，并完成一致性、范围与能力声明审查。当前状态为 `APPROVED_FOR_IMPLEMENTATION`；本规格已获用户整体批准，现进入实现计划阶段。

实现计划应按以下顺序交付 Codex：

1. 仓库创建与最小目录结构；
2. 核心治理 RED 基线与 Builder 效率 RED 对照场景；
3. 最小 `SKILL.md` 与单一权威 References；
4. Builder TOML 核心效率纪律与按需 `builder-debugging.md`；
5. Verifier TOML、最小验证包和证据复用规则；
6. Specialist 运行时协议、三个消息模板和临时 Worktree；
7. Compact Evidence、Convergence Snapshot 与中断恢复；
8. Windows 安装、升级、卸载、被动 Doctor、Specialist 能力记录与显式 Smoke Test；
9. GREEN 行为、EFF-01 至 EFF-07、Git / Worktree、Specialist 条件能力和完整三角色对照测试；
10. 规格一致性审查、安装包与最终验收回执。

实施必须遵循：

```text
先 RED
再最小实现
再 GREEN
再集成与实机验证
```

在实现开始前：

- 不创建最终 Skill 或 Agent 配置；
- 不声称角色隔离、效率收益或 Token 降低已经成立；
- 不跳过 RED 基线直接编写最终实现。
