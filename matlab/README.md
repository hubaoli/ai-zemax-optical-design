# AI Zemax Optical Design — MATLAB 规则包

本目录是仓库 Python Skill（`SKILL.md` + `scripts/*.py`）的 **MATLAB ZOS-API 对等规则**。功能目标相同：把光学需求变成可执行、可追溯的多阶段 Zemax 设计循环。实现语言从 Python/ZOSPy 换成 **MATLAB + .NET ZOS-API**。

> 默认约定（你已确认按此推进）：中文规则、英文 API 名；官方 MATLAB .NET 接口；Interactive Extension 优先；覆盖定焦、Profile 变焦、seed 适配与分阶段优化。不使用 DDE。

---

## 和 Python Skill 的关系

| | Python Skill（仓库根） | MATLAB 规则包（本目录） |
|--|------------------------|-------------------------|
| 连接 | ZOSPy → 原始 ZOS-API | `ZOSAPI_NetHelper` + `NET.addAssembly` |
| 入口 | `scripts/*_agent.py` | `matlab/scripts/*.m` + `matlab/scripts/+zos/` |
| 需求 / Profile | `examples/*.json` | **同一套 JSON**，`jsondecode` 读取 |
| 优化阶段 | baseline → feasibility → image-quality → field-balance → manufacturability | 相同，禁止改流程 |
| 产物 | `.zmx`、analyses、metrics、`design-log.jsonl` | 相同目录约定 |

不要把两套连接层混在一个进程里。选 MATLAB 就只走本目录规则。

---

## 读哪些文件

1. **`SKILL.md`** — AI 代理操作契约（先读这个）。
2. **`references/connection.md`** — 连接、许可证、InstanceId、清理。
3. **`references/matlab-zos-api-patterns.md`** — LDE / MFE / 分析 / 优化 / .NET 类型坑。
4. **`references/requirements-schema.md`** — JSON 在 MATLAB 中的读法与缺省。
5. **`references/merit-function.md`** — 分阶段评价函数与变量策略。
6. **`references/mce-zoom.md`** — 变焦 MCE、可变气隙、Profile。
7. **`references/result-parsing.md`** — 文本导出、UTF-16、metrics、日志。

---

## 环境

| 组件 | 要求 |
|------|------|
| OS | Windows 10/11 |
| OpticStudio | 2024 R1（实测基准），ZOS-API 覆盖 v20.3+ |
| MATLAB | **64 位**，能加载 .NET 4.x 程序集（R2016b+ 通常可用；推荐较新发行版） |
| 许可证 | 含 ZOS-API 的 OpticStudio 许可；`IsValidLicenseForAPI` 必须为 true |
| 位数 | MATLAB 与 OpticStudio **必须同为 64 位** |

---

## 快速用法（规则要求的操作顺序）

### 1. 冒烟连接

1. 打开 OpticStudio。
2. `Programming → MATLAB → Interactive Extension`（推荐），或准备 Standalone。
3. 在 MATLAB 中：

```matlab
cd(fullfile(repoRoot, 'matlab', 'scripts'))
connectionSmokeTest
% 期望: Connected: yes
```

### 2. 定焦

需求仍用仓库示例：

```matlab
cd(fullfile(repoRoot, 'matlab', 'scripts'))
automatedDesignAgent( ...
    'requirements', fullfile(repoRoot, 'examples', 'minimal_imaging_requirements.json'), ...
    'out', fullfile(repoRoot, 'output', 'my-design'), ...
    'mode', 'extension', ...
    'instanceId', 0);
```

### 3. 变焦（Profile 驱动）

```matlab
cd(fullfile(repoRoot, 'matlab', 'scripts'))
zoomLensDesignAgent( ...
    'requirements', fullfile(repoRoot, 'examples', 'apsc_18-55_f1.4_zoom_requirements.json'), ...
    'out', fullfile(repoRoot, 'output', 'aps-c-zoom'), ...
    'mode', 'extension', ...
    'instanceId', 0);
```

自定义变焦：复制 `examples/profiles/apsc_18_55_f14_zoom_profile.json`，在需求 JSON 的 `lens_profile` 指向新文件。**不要为换一款变焦去改 MATLAB 结构硬编码。**

无 Zemax 时先跑 Profile 单元测试：

```matlab
cd(fullfile(repoRoot, 'matlab', 'tests'))
testZoomLensProfile
```

### 4. 产物布局（与 Python 版对齐）

```
output/<job>/
├── zoom_baseline.zmx              % 定焦则为 baseline.zmx
├── zoom_feasibility.zmx
├── zoom_image-quality.zmx
├── zoom_field-balance.zmx
├── zoom_manufacturability.zmx
├── design-log.jsonl
├── metrics-*.json
├── requirements.json
└── analyses/
    ├── baseline/
    ├── feasibility/
    ├── image-quality/
    ├── field-balance/
    └── manufacturability/
```

---

## 代理在本仓库中的工作方式

用户要求「用 MATLAB 跑与本项目相同的设计循环」时：

1. 加载 `matlab/SKILL.md`，不要加载根目录 Python `SKILL.md` 当运行时指令（schema 仍可共用）。
2. 只加载当前任务需要的 `matlab/references/*`。
3. 复用 `examples/` JSON，不要另发明一套字段名。
4. 优先调用已有 `matlab/scripts/*.m`；缺能力时再补 `+zos` 原语，不要另起连接层。
5. 没有 OpticStudio 的机器上：仍可交付脚本与规则，但必须明确 **未实测连接**，不得宣称设计已收敛。

---

## 已知限制（MATLAB 侧）

- MATLAB 对 .NET `out` 参数、重载方法、枚举赋值比 C# 更挑剔；见 patterns 文档。
- `NET.addAssembly` 在同一 MATLAB 会话中重复加载可能报错，连接函数必须幂等。
- Interactive Extension 由 OpticStudio 生成的 `MATLABZOSConnectionN.m` 可作连接样板，但设计循环应放在独立函数中，避免把业务代码写进连接样板。
- 中文路径：优先把 `out` 放到 ASCII 绝对路径。
- 官方 MATLAB 示例里优化向导调用 `Apply()`；本仓库 Python 侧在 2024 R1 上发现需要 `OK()`。MATLAB 实现必须两者兼容。
