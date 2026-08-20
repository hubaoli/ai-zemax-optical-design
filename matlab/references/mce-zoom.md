# MATLAB 变焦：Profile、MCE、可变气隙

与 `scripts/zoom_lens_design_agent.py` 行为对齐。换变焦结构只换 JSON Profile，不改 MATLAB 处方硬编码。

---

## Profile 加载

`requirements.lens_profile` 可以是：

- 相对需求文件的路径（如 `profiles/apsc_18_55_f14_zoom_profile.json`）
- 内嵌 struct

```matlab
function profile = loadLensProfile(req, reqDir)
    ref = localGet(req, 'lens_profile', []);
    if isstruct(ref)
        profile = normalizeLensProfile(ref);
        return
    end
    if ischar(ref) || (isstring(ref) && strlength(ref) > 0)
        p = char(ref);
        if isempty(fileparts(p)) || ~startsWith(p, filesep)
            p = fullfile(reqDir, p);
        end
        profile = normalizeLensProfile(jsondecode(fileread(p)));
        profile.source_path = p;
        return
    end
    error('Zoom design blocked: lens_profile is required. Do not invent a zoom architecture.');
end
```

无 profile 的变焦任务：**阻塞**，不要用默认三片凑数去「先跑起来」（Python 里有 generic fallback，仅用于内部测试；面向用户的 MATLAB 规则更严）。

规范化要求：

- `surfaces[]` 非空，`surface` 索引唯一
- `radius` / `thickness`：数字或 `"infinity"`
- `variable_gaps[]`：`name`、`surface`、`default_mm`、可选 `per_config`
- 表面带 `variable_gap` 标签但 gaps 列表没有时，按该表面厚度补一条
- `merit.bfl_surface`、`merit.max_field_index` 缺省：像面前一面、3
- `mce.include_aperture_operand` / `include_field_operand` 缺省 true

---

## 按 Profile 建 LDE

1. `TheSystem.New(false)`
2. 波长、视场、孔径来自 requirements
3. 将 LDE 扩到 `max(surface)+1`（含物体面 0 与像面）
4. 对每个有限面 `GetSurfaceAt` 写 Radius / Thickness / Material
5. `stop: true` 的面：`TheSystem.LDE.StopSurface = n`

物体面（surface 0）不要用 `GetSurfaceAt(0)` 乱写；Zemax LDE 物体面是表面 0，API 中 `GetSurfaceAt(0)` 在部分版本可用。若不可用，保持 New() 默认物体面，只从表面 1 写到像面。

---

## 气隙初值优先级

与 Python `resolve_gap_initial_value()` 相同，禁止按下标盲取：

1. 该变焦组态的 `gap_values_mm` 里按 gap **名字**（其次按表面号字符串）
2. `variable_gaps.per_config` 里键名等于或包含组态名（大小写不敏感，如 `wide` 匹配 `wide_18mm`）
3. `default_mm`

---

## MCE 搭建

```matlab
mce = TheSystem.MCE;
nCfg = numel(zoomConfigs);

while mce.NumberOfConfigurations < nCfg
    mce.AddConfiguration(true);      % bool，不是 int
end
while mce.NumberOfConfigurations > nCfg
    mce.DeleteConfiguration(mce.NumberOfConfigurations);
end

needed = numel(variableGaps) + double(includeAper) + double(includeField);
while mce.NumberOfOperands < needed
    mce.AddOperand();
end
```

Operand 类型必须用枚举：

```matlab
THIC = ZOSAPI.Editors.MCE.MultiConfigOperandType.THIC;
APER = ZOSAPI.Editors.MCE.MultiConfigOperandType.APER;
YFIE = ZOSAPI.Editors.MCE.MultiConfigOperandType.YFIE;

op = mce.GetOperandAt(int32(i));
op.ChangeType(THIC);
op.Param1 = int32(gap.surface);      % 厚度所在表面
op.GetOperandCell(int32(cfg)).DoubleValue = gapVal;
```

建议顺序：

1. 每个 variable gap 一条 `THIC`
2. 可选 `APER`：各组态 F/#（`cfg.f_number` 或 `mce.default_f_number`）
3. 可选 `YFIE`：恒定像高（`cfg.image_height_mm` 或 `mce.default_image_height_mm`）

`ChangeType` 禁止传 `'THIC'` 字符串。

当前组态：

```matlab
try
    mce.SetCurrentConfiguration(int32(cfg));
catch
    mce.CurrentConfiguration = int32(cfg);
end
```

导出分析前必须切组态。优化时 THIC 各组态 cell `MakeSolveVariable`（若 profile `mce_variable_operand_types` 包含 `THIC`）。

---

## 手术式变量（变焦）

只使用 profile.variables：

- `feasibility_radius_surfaces`
- `image-quality_radius_surfaces` / `image-quality_thickness_surfaces`
- `field-balance_*`
- `manufacturability_*`
- `material_surfaces`
- `mce_variable_operand_types`（默认 `["THIC"]`）

不要对所有玻璃面放开半径。这是 v1.3 相对硬编码 APS-C 处方的核心差异。

---

## 每组态分析

每个阶段 × 每个组态导出：spot、FFT MTF、wavefront、ray fan、field curvature/distortion。文件名：

```
analyses/<stage>/spot_<configName>.txt
analyses/<stage>/mtf_<configName>.txt
...
```

`configName` 用需求里的 `name`（如 `wide_18mm`），不要用 `config_1` 除非没有名字。

---

## 与定焦 agent 的分界

| 条件 | 入口 |
|------|------|
| 存在 `zoom_configurations` 且非空 | `zoomLensDesignAgent` |
| 否则 | `automatedDesignAgent` |

不要在定焦脚本里半套 MCE。
