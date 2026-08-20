# MATLAB 结果解析与日志

自动化设计需要可比较的指标，而不是只留下 Zemax 文本。规则与根目录 `references/result-parsing.md` 对齐，补充 MATLAB 编解码差异。

---

## 每阶段产物

| 文件 | 规则 |
|------|------|
| 镜头 | 绝对路径 `zoom_<stage>.zmx` 或 `stage-<stage>.zmx` |
| 原始分析 | `analyses/<stage>/`，变焦带 `_<configName>` 后缀 |
| 指标 | `metrics-<stage>.json`（UTF-8） |
| 事件 | 追加 `design-log.jsonl`（每行一个 JSON 对象） |
| 阶段摘要 | `stage-<stage>.json` |

`save_every_stage=true` 时即使阶段被拒绝也要保留文件，并在 JSON 里 `accepted: false`。

---

## 核心指标键（稳定，禁止改名）

```
merit_value
efl_mm
bfl_mm
f_number
na
total_track_mm
rms_spot_um
mtf                  % 对象：频率 → 对比度
distortion_percent
wavefront_rms_waves
constraint_violations
```

变焦再加：

```
num_configurations
per_config.<name>.*  % 同上键，按组态拆分
```

比较阶段时用这些键。缺测写 `null`（JSON）/`[]`（MATLAB 编码前转成 JSON null），不要省略键。

---

## 文本编码

Zemax `GetTextFile` 经常是 **UTF-16 LE**（BOM `FF FE`）。

```matlab
function txt = readTextRobust(path)
    fid = fopen(path, 'rb');
    bytes = fread(fid, inf, '*uint8');
    fclose(fid);
    if numel(bytes) >= 2 && bytes(1) == 255 && bytes(2) == 254
        txt = native2unicode(bytes, 'UTF-16LE');
        return
    end
    if numel(bytes) >= 2 && bytes(1) == 254 && bytes(2) == 255
        txt = native2unicode(bytes, 'UTF-16BE');
        return
    end
    try
        txt = native2unicode(bytes, 'UTF-8');
    catch
        txt = native2unicode(bytes, 'latin1');
    end
end
```

解析失败时 **保留原始 txt**，在 metrics 的 `parser_notes` 记录失败，不要删除分析文件。

把 OpticStudio UI 语言切到 English 可显著降低正则失败率（见 connection 规则）。

---

## 解析策略

1. 优先 API 数值：`GetResults()` 的 DataGrid / DataSeries（`.double`），以及 MFE operand `.Value`。
2. API 无结构时再解析文本。
3. 正则应对大小写与 `F/#` / `EFL` / `RMS spot` 等；中文 UI 文本只作为 fallback。
4. 报告 **每视场、每波长、每组态** 的退化，禁止只给平均值掩盖边缘视场。

MTF：按需求 `targets.mtf[].frequency_lp_per_mm` 取值，记录实测对比度 vs `min_contrast`。

---

## 日志事件

`design-log.jsonl` 每行：

```json
{"time":"2026-08-21T12:00:00","event":"stage-start","stage":"feasibility"}
```

至少包含：

- `connect`（mode、instanceId、license）
- `seed-select` 或 `seed-blocked`
- `profile-load`（变焦）
- `stage-start` / `stage-finish`（含 merit、accepted、paths）
- `assumption`（一旦引入立刻写）
- `error`

MATLAB 写 JSONL：

```matlab
function appendJsonl(path, event)
    event.time = char(datetime('now', 'Format', 'yyyy-MM-dd''T''HH:mm:ss'));
    fid = fopen(path, 'a', 'n', 'UTF-8');
    fprintf(fid, '%s\n', jsonencode(event));
    fclose(fid);
end
```

`jsonencode` 对非 ASCII 会 `\u` 转义，可接受。逻辑值会变成 `true/false`。

---

## 阶段比较

新候选对比：baseline、上一接受阶段、用户 targets。任一硬约束失败 → 拒绝。日志必须能回答：相对 seed 改了什么、相对上一阶段改了什么。
