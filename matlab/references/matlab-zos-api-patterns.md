# MATLAB ZOS-API 模式（OpticStudio v20.3+ / 2024 R1）

索引从 1 开始：表面、波长、视场、组态、MFE/MCE operand 均为 1-based。MATLAB 同样 1-based，**不要把 Python 的 0 基习惯带过来**（Python 侧 LDE 仍是 Zemax 的 1-based API）。

---

## 入口对象

```matlab
TheSystem     = TheApplication.PrimarySystem;
TheLDE        = TheSystem.LDE;
TheMFE        = TheSystem.MFE;
TheMCE        = TheSystem.MCE;
TheSystemData = TheSystem.SystemData;
```

| 需求 | MATLAB |
|------|--------|
| 新文件 | `TheSystem.New(false);` |
| 打开 | `TheSystem.LoadFile(absPath, false);` |
| 保存 | `TheSystem.Save();` |
| 另存 | `TheSystem.SaveAs(absPath);` |
| 顺序模式 | `TheSystem.MakeSequential();` |
| 样本目录 | `char(TheApplication.SamplesDir)` |

`.zar` 用 `TheSystem.Tools.OpenRestoreZAR()`，设文件名与输出目录后 `RunAndWaitForCompletion(); Close();`。同一时刻只能开一个 Tool。

---

## .NET 类型转换（MATLAB 特有）

| 情况 | 规则 |
|------|------|
| `System.String` → MATLAB | `char(netStr)` |
| 路径传给 API | 优先 `System.String.Concat(...)` 或已确认可用的 MATLAB char 绝对路径 |
| 浮点结果 | `double(x)` |
| 整数形参（表面号、组态号、InstanceId） | `int32(n)` |
| 逻辑 | MATLAB `true`/`false` |
| 枚举 | 完整限定名，例如 `ZOSAPI.Editors.MCE.MultiConfigOperandType.THIC`，禁止字符串、禁止随便塞 double |
| `out` 数组 | `NET.createArray('System.Double', n)`，调用后再 `.double` |
| 分析 DataSeries | `series.XData.Data.double` |

`out` 参数示例：

```matlab
index = NET.createArray('System.Double', numWaves);
TheSystem.LDE.GetIndex(int32(surfNum), int32(numWaves), index);
n = index.double;
```

查看成员：`methods(obj)` / `methodsview(obj)`。Intellisense 需要脚本未结束（断点）或 Interactive 连接保持。

---

## System Explorer

```matlab
ap = TheSystem.SystemData.Aperture;
ap.ApertureType  = ZOSAPI.SystemData.ZemaxApertureType.FloatByStopSize; % 按需求选择
% 常用：EntrancePupilDiameter / ImageFNumber / FloatByStopSize
ap.ApertureValue = 4.0;

TheSystem.SystemData.MaterialCatalogs.AddCatalog('SCHOTT');

waves = TheSystem.SystemData.Wavelengths;
waves.SelectWavelengthPreset(ZOSAPI.SystemData.WavelengthPreset.FdC_Visible);
% 或逐条：
% waves.GetWavelength(1).Wavelength = 0.58756180;
% waves.AddWavelength(0.48613270, 1.0);

fields = TheSystem.SystemData.Fields;
fields.SetFieldType(ZOSAPI.SystemData.FieldType.Angle);
f1 = fields.GetField(1);
f1.X = 0; f1.Y = 0; f1.Weight = 1;
fields.AddField(0, 38.2, 1.0);
```

孔径类型必须用枚举，不要对 drop-down 赋字符串。

---

## LDE

```matlab
TheLDE.InsertNewSurfaceAt(int32(1));
surf = TheLDE.GetSurfaceAt(int32(2));
surf.Radius    = 50;
surf.Thickness = 5;
surf.Material  = 'N-BK7';          % 不要 MaterialName
surf.Comment   = 'G1a';
surf.RadiusCell.MakeSolveVariable();
surf.ThicknessCell.MakeSolveVariable();

TheSystem.LDE.StopSurface = int32(3);
% 同时可：
% surfStop.IsStop = true;
```

- 无穷半径/厚度：不要传 MATLAB `Inf` 给所有属性；profile 里 `"infinity"` 在物体面按 Zemax 惯例处理（物体厚度无穷）。有限光学面不要设 Inf。
- 非球面改类型：`settings = surf.GetSurfaceTypeSettings(ZOSAPI.Editors.LDE.SurfaceType.EvenAspheric); surf.ChangeType(settings);`
- 参数列：`surf.GetSurfaceCell(ZOSAPI.Editors.LDE.SurfaceColumn.Par1).DoubleValue = ...`

---

## 分析

优先专用工厂；没有再用 `New_Analysis(AnalysisIDM.*)`。

```matlab
spot = TheSystem.Analyses.New_StandardSpot();
spot.ApplyAndWaitForCompletion();
spot.GetResults().GetTextFile(absTxtPath);
spot.Close();
```

| 分析 | 工厂 | AnalysisIDM |
|------|------|-------------|
| 点列图 | `New_StandardSpot` | `StandardSpot` |
| FFT MTF | `New_FftMtf` | `FftMtf` |
| 波前 | `New_WavefrontMap` | `WavefrontMap` |
| 光线扇 | `New_RayFan` | `RayFan` |
| 场曲/畸变 | `New_FieldCurvatureAndDistortion` | `FieldCurvatureAndDistortion` |

流程：打开 →（可选）`GetSettings()` 修改 → `ApplyAndWaitForCompletion()` → `GetResults()` → `GetTextFile` 和/或 DataGrid/DataSeries → **`Close()`**。

无专用 settings 时：`settings.SaveTo(cfg); settings.ModifySettings(cfg, key, value); settings.LoadFrom(cfg);`。键名见 ZPL `MODIFYSETTINGS`。

变焦：先 `TheSystem.MCE.SetCurrentConfiguration(int32(cfg))`（失败则试 `CurrentConfiguration = cfg`），再开分析。每个组态导出独立文本。

---

## 优化向导与 MFE

```matlab
mfe = TheSystem.MFE;
mfe.DeleteAllRows();   % 重建前清空
wiz = mfe.SEQOptimizationWizard;
wiz.Data = 1;          % 按官方示例：RMS Spot；若 2024 绑定不同，记录实际枚举/整型含义
wiz.Ring = 2;
wiz.Arm  = 0;
wiz.OverallWeight = 1;
wiz.IsGlassUsed = true;
wiz.IsAirUsed = true;
wiz.GlassMin = 3.0; wiz.GlassMax = 15.0; wiz.GlassEdge = 3.0;
wiz.AirMin = 0.5;  wiz.AirMax = 1000.0; wiz.AirEdge = 0.5;
try
    wiz.Apply();
catch
    wiz.OK();          % 2024 R1 Python 侧实测
end
```

手动 operand：

```matlab
op = mfe.AddOperand();
op.ChangeType(ZOSAPI.Editors.MFE.MeritOperandType.EFFL);
op.Target = 50.0;
op.Weight = 10.0;
```

读值：先 `mfe.CalculateMeritFunction()` 或 `OpenMeritFunctionCalculator`，再 `mfe.GetOperandAt(i).Value`。

**禁止** `TheSystem.Tools.OpenMeritFunction()` 当编辑器入口。

---

## 局部优化

```matlab
TheSystem.Tools.RemoveAllVariables();   % 仅当本阶段要重设变量时
% ... MakeSolveVariable ...
LocalOpt = TheSystem.Tools.OpenLocalOptimization();
if ~isempty(LocalOpt)
    LocalOpt.Algorithm = ZOSAPI.Tools.Optimization.OptimizationAlgorithm.DampedLeastSquares;
    LocalOpt.Cycles    = ZOSAPI.Tools.Optimization.OptimizationCycles.Automatic;
    LocalOpt.NumberOfCores = int32(8);
    initMF = double(LocalOpt.InitialMeritFunction);
    LocalOpt.RunAndWaitForCompletion();
    finalMF = double(LocalOpt.CurrentMeritFunction);
    LocalOpt.Close();
end
```

- `Cycles` 禁止赋 `5` 这种 double（Python.NET 3.0 同样禁止；MATLAB 同样要枚举）。
- 不要只信一个 merit 标量：检查几何、边缘厚度、各视场/各组态。
- Tool 用完必须 `Close()`，否则下一个 Tool 打不开。

---

## 存盘路径

```matlab
absLens = char(java.io.File(lensPath).getAbsolutePath());  % 或 use fullfile + pwd
if any(absLens > 127)
    warning('Non-ASCII path: OpticStudio SaveAs may fail silently. Prefer ASCII out dir.');
end
TheSystem.SaveAs(absLens);
```

输出根目录默认 `output/<job>/`，相对仓库根解析为绝对路径。

---

## 官方示例对照

OpticStudio 安装目录 `ZOS-API Sample Code\MATLAB\`：

- `MATLABStandalone_basic_seq` / Example 11：建系统、光阑、Spot
- `MATLABStandalone_15_Seq_Optimization.m`：向导 + 局部优化
- Interactive：`Programming → MATLAB → Interactive Extension` 生成连接样板

设计循环以本仓库规则为准；官方示例只作 API 语法参考。
