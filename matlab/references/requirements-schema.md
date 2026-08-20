# MATLAB 侧需求 Schema

规范化形状与仓库根 `references/requirements-schema.md`、`examples/*.json` **完全相同**。本文件只规定 MATLAB 如何读、如何填缺省、禁止改哪些字段名。

---

## 读取

```matlab
raw = fileread(reqPath);           % JSON 应为 UTF-8
req = jsondecode(raw);
```

`jsondecode` 行为：

- 对象 → `struct`
- 对象数组 → `struct` 数组（用 `req.fields(i)` 而不是 `req.fields{i}`）
- 纯数组 → double 或 cell
- 缺键 → 报错或字段不存在：一律 `isfield` / `localGet`

```matlab
function v = localGet(s, name, default)
    if isstruct(s) && isfield(s, name) && ~isempty(s.(name))
        v = s.(name);
    else
        v = default;
    end
end
```

路径字段（`input_lens`、`lens_profile`、`seed_design.selected_case_path`）相对 **需求 JSON 所在目录** 解析，再变成绝对路径。

---

## 必须保留的字段名

不要把 `efl_mm` 改成 `EFL`，不要把 `zoom_configurations` 改成 `configs`。下游日志与 Python 产物要对齐。

最小形状见根目录 schema。变焦额外：

- `lens_profile`：字符串路径或内嵌对象（MATLAB 为 struct）
- `constraints.zoom_configurations[]`：`name`、`efl_mm`、`f_number`、可选 `image_height_mm`、可选 `gap_values_mm`

Profile 文件形状见 `examples/profiles/apsc_18_55_f14_zoom_profile.json` 与 `matlab/references/mce-zoom.md`。

---

## 无穷与空

| JSON | MATLAB |
|------|--------|
| `"infinity"` / `"+inf"` | 物体面厚度：按 Zemax 物体面惯例，不要对有限面赋 `Inf` |
| `null` | `jsondecode` 常变为 `[]`，当「未设置」 |
| 空字符串材料 | 空气 |

---

## 模式

| `mode` / 输入 | 行为 |
|---------------|------|
| 有 `input_lens` 且文件存在 | `LoadFile`，再对照 targets 适配 |
| `seed_design.selected_case_path` | 同上，记 provenance |
| `new_design` + `lens_profile` | 按 profile 建 sequential + MCE |
| `new_design` 无 profile 无 seed | 定焦可建最小起始模型；**变焦则阻塞**，要求 profile 或 seed |

---

## automation

```json
"automation": {
  "max_stages": 5,
  "max_optimization_seconds_per_stage": 120,
  "save_every_stage": true
}
```

阶段名固定（日志与文件名使用这些英文 slug）：

`baseline`、`feasibility`、`image-quality`、`field-balance`、`manufacturability`

MATLAB 实现可用秒数做软超时（`tic/toc` 后不再开下一轮优化），但不要因此跳过未跑完阶段的存盘。

---

## 与 Python 示例共用

直接引用，不要复制改名：

- `examples/minimal_imaging_requirements.json`
- `examples/apsc_18-55_f1.4_zoom_requirements.json`
- `examples/seeded_complex_zoom_requirements.json`
- `examples/telescope_12x60_requirements.json`
- `examples/profiles/apsc_18_55_f14_zoom_profile.json`
