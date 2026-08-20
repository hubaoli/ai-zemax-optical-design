---
name: ai-zemax-matlab-optical-design
description: "Automated optical design agent for Ansys Zemax OpticStudio through MATLAB ZOS-API (.NET). Use when the agent should turn optical requirements or an existing .zmx/.zos/.zar file into an executable MATLAB design loop: connect via Interactive Extension or Standalone, parse requirements, create or load a lens, run baseline analyses, choose variables and constraints, build a merit function, run staged optimization, compare iterations, save lens files, and produce machine-readable design logs. Supports prime lenses and multi-configuration zoom systems. Do not use legacy DDE."
---

# AI Zemax Optical Design — MATLAB ZOS-API

把本 Skill 当作 **MATLAB 驱动的 Zemax 自动化设计代理**。交付物是可执行的 MATLAB ZOS-API 代码与设计产物，而不是口头光学建议。

目标环境：Windows 10/11 + Ansys Zemax OpticStudio v20.3+（实测基准 2024 R1）+ MATLAB（64 位，与 OpticStudio 位数一致）。

连接层：**MATLAB .NET Interop + `ZOSAPI_NetHelper`**。不要用已废弃的 DDE，不要把 Python/ZOSPy 代码直接粘进 MATLAB。

配套参考（按需加载，不要一次全读）：

- `matlab/references/connection.md`
- `matlab/references/matlab-zos-api-patterns.md`
- `matlab/references/requirements-schema.md`
- `matlab/references/merit-function.md`
- `matlab/references/result-parsing.md`
- `matlab/references/mce-zoom.md`

需求 JSON 与镜头 Profile 与仓库根目录 `examples/`、`references/requirements-schema.md` **共用同一套 schema**，MATLAB 用 `jsondecode` 读取。

---

## Operating Contract

始终推进到这些产物：

1. 规范化需求 JSON（含显式 assumptions）。
2. 若存在更接近的官方示例 / 目录 seed，记录 seed 选择与结构差距。
3. 可运行的 MATLAB ZOS-API 脚本（或对脚手架的补丁），而不是伪代码。
4. 优化前的基线分析导出。
5. 分阶段的变量 / 约束 / 评价函数计划。
6. 每个被接受阶段的版本化镜头文件。
7. 最终设计日志：指标、约束、变更、未解决风险。

用户没有明确只要理论时，不要停在概念建议。

复杂镜头族：把多轮评分 / 分阶段优化脚手架视为稳定基础设施，本轮不要重写流程。

---

## Hard Constraints

- 有更接近的官方或目录 seed 时，不要凭空发明起始结构。
- 不要悄悄从 seed 工作流切到从零设计。
- 不要把问题扩大到用户未要求的镜头类型、焦距范围、孔径或封装限制之外。
- 弱相似 seed 不可当作可用，除非把 mismatch 明确写入日志。
- 在 seed 选择、目标规范化、结构差距列表完成之前，不要开始优化。
- seed-to-target 差距尚未交代时，不要宣称设计已适合目标。
- 缺失结构细节不要猜；记为 assumption 或向用户确认。
- 不要为了更容易而改掉用户要求的镜头类别。
- 不要替换分阶段优化逻辑；保持 **feasibility → image quality → field balance → manufacturability**，除非用户明确要求别的策略。
- **禁止 DDE / ZOS-API COM 旧桥 / 把 Python.NET 习惯直接当 MATLAB 语法。**
- Interactive Extension 会话 **不要** 调用 `CloseApplication()`（会关掉用户正在用的 OpticStudio）。Standalone 结束时必须 `CloseApplication()`。
- 同一光学系统同一时刻只开一个 `Tools` 工具；分析窗口用完必须 `Close()`。

---

## Complex-Design Guardrails

- 难镜头取保守解释：结构保真、收敛稳定、变更可追溯，优先于激进优化。
- 大族类不匹配视为阻塞，直到结构差距被解释并记入日志。
- 宁可焦距不完全匹配，也要选光学族、变焦行为、孔径区间、封装最接近的 seed。
- 最佳 seed 只是部分匹配时，先记录 mismatch 与适配负担再继续。
- 不要为了强行收敛而盲目增加自由度；只在当前阶段与差距分析证明需要时放开。

---

## Automation Flow

### 1. Parse input

- 按 `references/requirements-schema.md`（仓库根）与 `matlab/references/requirements-schema.md` 规范化。
- MATLAB 读取：`req = jsondecode(fileread(reqPath));`，缺字段用 `isfield` / 本地默认，不要静默发明硬约束。
- 若提供 `.zmx` / `.zos` / `.zar`，先 `LoadFile` / RestoreZAR，再提取视场、波长、孔径、组态、处方、评价函数状态。
- 新设计：先搜最接近的官方示例或目录镜头（同结构族），再适配；不要从空白系统发明架构。
- 快变焦成像（如 F/1.4、3×、18–55 mm 风格）优先结构相似的 zoom seed，并记录匹配轴。
- 没有明确相关 seed 时，停下来报告缺失的结构基础，不要即兴发明。
- 优化前必须写下 structural gap list。

### 2. Create or load the Zemax model

- 已有模型优先加载。
- 新设计：先选 seed，再适配焦距、孔径、视场、封装。
- 无合适 seed：用一阶需求建最小 sequential 起始模型，设置表面、孔径、视场、波长、光阑、像面、材料。
- 变焦：优化前完成 MCE（见 `matlab/references/mce-zoom.md`）。
- 初始适配阶段保持 seed 架构稳定；增删或重排组必须记原因。

### 3. Run baseline evaluation

导出：一阶数据、处方、点列图、FFT MTF、波前、光线扇、场曲/畸变。相关时再加领域分析。把原始文本解析成 metrics JSON。

### 4. Select variables and constraints

分阶段放开：对焦/气隙 → 曲率 → 厚度 → 玻璃替换 → 非球面 → 多重组态 solve → 公差补偿器。

先编码硬可行性约束，再谈像质。未获用户批准，不要放开会破坏当前结构意图的参数。

### 5. Build and run the merit function

使用 `matlab/references/merit-function.md`。阶段：feasibility、image quality、field balance、manufacturability，可选 tolerance readiness。每阶段存镜头与 metrics。阶段失败就修当前阶段，不要跳到后面。

### 6. Compare and accept iterations

对照：基线、上一接受设计、用户目标。拒绝靠隐藏几何/玻璃/孔径/视场/公差失败换来的单项变好。保留 seed provenance。未经明确批准，拒绝改变镜头类别、变焦行为或复杂度包络的候选。优化中产生的新假设立刻记日志。

### 7. Report outputs

返回：最终镜头路径、中间镜头路径、分析输出路径、设计日志路径、相对目标的性能、assumptions、仍需人工检查的项。

---

## MATLAB 脚本职责（对应 Python Skill）

| Python | MATLAB 应实现的入口 | 职责 |
|--------|---------------------|------|
| `scripts/zos_design_primitives.py` | `matlab/scripts/zosDesignPrimitives.m`（或 `+zos/` 包） | 连接、分析导出、存盘、指标、局部优化原语 |
| `scripts/automated_design_agent.py` | `matlab/scripts/automatedDesignAgent.m` | 定焦 / seed 设计循环 |
| `scripts/zoom_lens_design_agent.py` | `matlab/scripts/zoomLensDesignAgent.m` | Profile 驱动变焦：MCE、可变气隙、分阶段优化 |
| `scripts/connection_smoke_test.py` | `matlab/scripts/connectionSmokeTest.m` | Interactive / Standalone 冒烟 |
| `scripts/design_single_lens_pythonnet.py` | `matlab/scripts/designSingleLensStandalone.m` | 无脚手架时的单透镜回退（仍走 ZOS-API，不走 DDE） |

脚本已在 `matlab/scripts/`。代理应调用这些入口；只有缺能力时才增补 `+zos` 原语，不要另起连接层。无 OpticStudio 时仍可跑 `matlab/tests/testZoomLensProfile.m`。

---

## Connection Diagnostics

默认 **Interactive Extension**：OpticStudio 必须已打开，并处于 extension-ready。

健康连接：

- Standalone：`CreateNewApplication()` 返回应用，`IsValidLicenseForAPI == true`，`PrimarySystem` 非空。
- Interactive Extension：`ConnectAsExtension(instanceId)` 返回应用，许可证有效，`PrimarySystem` 非空。`instanceId` 默认为 `0`（任一可用实例），必须参数化，禁止写死魔法数字（除默认 0 外）。

若已有连接对象但 `IsValidLicenseForAPI == false` 或 `PrimarySystem` 为空：视为不可用，先修 OpticStudio 扩展/许可证，再跑设计循环。

Standalone 弹出异常对话框或超时后，不要反复重试。清对话框，必要时重启 OpticStudio，再先验证 Interactive Extension。

位数必须一致：64 位 MATLAB ↔ 64 位 OpticStudio。混用会在加载类型时失败。

详细步骤见 `matlab/references/connection.md`。

---

## MATLAB / 2024 R1 API 硬规则（摘要）

完整列表见 `matlab/references/matlab-zos-api-patterns.md`。

- 光阑：`TheSystem.LDE.StopSurface = N`，并可同时 `surf.IsStop = true`。不要依赖不存在的 `MakeSurfaceStop()`。
- 评价函数：直接用 `TheSystem.MFE`，不要 `Tools.OpenMeritFunction()`。
- 优化向导：`wizard = TheSystem.MFE.SEQOptimizationWizard`。属性名单数 `Data` / `Ring` / `Arm`。应用时 **先 `Apply()`，失败再 `OK()`**（MATLAB 官方示例用 `Apply()`；部分 2024 R1 绑定暴露 `OK()`）。
- 局部优化：`LocalOpt = TheSystem.Tools.OpenLocalOptimization();` 然后设枚举算法/循环次数，再 `RunAndWaitForCompletion(); Close();`。`Cycles` 必须是 `ZOSAPI.Tools.Optimization.OptimizationCycles` 枚举，禁止赋 MATLAB `double`。
- MCE：`AddConfiguration(true)` 接受逻辑值；`ChangeType(ZOSAPI.Editors.MCE.MultiConfigOperandType.THIC)` 必须用枚举，禁止字符串。
- 材料：`surf.Material = 'N-BK7'`，不要 `MaterialName`。
- `SaveAs` / `GetTextFile` 必须用绝对路径；中文或非 ASCII 目录可能静默失败，输出目录优先纯 ASCII。
- .NET 字符串用 `char()`，数值用 `double()`，整数形参优先 `int32()`。`out` 数组用 `NET.createArray('System.Double', n)`。
- Zemax 导出文本可能是 UTF-16；先 UTF-16 再 UTF-8。
- 同一 `TheSystem` 同时只能跑一个 Tool。

---

## Seed-Design Policy

复杂结构（尤其变焦）默认策略：

1. 找同结构族中最近的官方示例或目录/参考镜头。
2. 按这些轴比较：焦距跨度、孔径与入瞳、组/片数、变焦机构与共轭、视场与像面格式、筒长与后焦距、玻璃策略与非球面。
3. 选最佳结构匹配为 seed，显式记录 gaps。
4. 小步适配，不要从零重画。
5. seed 来源、mismatch、人工结构编辑必须出现在最终设计日志里。

F/1.4、3×、18–55 mm 一类任务：偏向最近的 zoom imaging seed，即使焦距不是精确匹配。

---

## 验收清单（代理在宣称完成前必须勾选）

- [ ] 连接模式写明（extension / standalone），许可证与 `PrimarySystem` 已验证。
- [ ] 需求 JSON 已规范化，assumptions 已列出。
- [ ] seed 或「无合适 seed」的阻塞报告已写出。
- [ ] 变焦任务：MCE 组态数 = 需求组态数，可变气隙已按 profile 初始化。
- [ ] baseline 分析已导出且未优化。
- [ ] 四阶段（加 baseline）均有镜头文件与 metrics。
- [ ] 设计日志 `design-log.jsonl` 可逐事件回放。
- [ ] Standalone 已关闭应用；Interactive 未误关 OpticStudio。
