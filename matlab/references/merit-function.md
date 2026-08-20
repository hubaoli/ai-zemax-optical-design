# MATLAB 分阶段评价函数与变量策略

与仓库根 `references/merit-function.md` 同策略。本文件给出 MATLAB ZOS-API 落地规则。阶段失败只修当前阶段，不跳步。

每阶段结束后：存镜头、导出分析、写 `metrics-*.json`、追加 `design-log.jsonl`。

---

## 阶段总表

| 阶段 | 目的 | 变量（定焦） | 变量（变焦，以 profile 为准） |
|------|------|--------------|-------------------------------|
| baseline | 只评价，不优化 | 无 | 无 |
| feasibility | 打中 EFL、F/#、BFL、像高、筒长 | 像距/气隙 + 少量光焦度半径 | MCE 可变气隙 + `feasibility_radius_surfaces` + BFL |
| image-quality | RMS 点列、波前、色差、场曲、像散 | 更多半径 + 选定厚度 | profile 的 IQ 半径/厚度 |
| field-balance | 中心/0.7/全视场、波长、组态拉齐 | 更全半径+厚度 | profile 的 FB 列表 |
| manufacturability | 直径、矢高、边缘厚度、入射角、胶合、玻璃成本 | 半径+厚度+受控玻璃替换 | profile 的 MFR 列表 + `material_surfaces` |
| tolerance-readiness（可选） | 补偿器与粗公差 | 用户明确要求才做 | 同左 |

接受迭代的条件：目标指标变好 **且** 硬约束未破。拒绝中心视场变好但边缘/其他组态变差。

---

## 向导底板（每阶段重建 MFE 时）

```matlab
mfe = TheSystem.MFE;
mfe.DeleteAllRows();
wiz = mfe.SEQOptimizationWizard;
% RMS spot / centroid / Gaussian quadrature — 与 Python zoom agent 意图对齐
wiz.Data = 1;
wiz.Ring = 2;
wiz.Arm  = 0;
wiz.OverallWeight = 1;
wiz.IsGlassUsed = true;
wiz.IsAirUsed = true;
% 边界来自 requirements.constraints
try, wiz.Apply(); catch, wiz.OK(); end
```

向导失败则手动加 TRAC（或 RSRE）operand，按波长 × 视场 × 组态展开，权重均匀，禁止只加轴上。

然后按阶段追加一阶与制造 operand（`ChangeType(ZOSAPI.Editors.MFE.MeritOperandType.*)`）：

| Operand | 用途 | 何时加重 |
|---------|------|----------|
| `EFFL` | 每组态焦距 | feasibility 权重大 |
| `WFNO` | 工作 F/# | feasibility |
| `REAY` | 最大视场像高 | feasibility / 恒定像面 |
| `CTVA` / BFL 面厚度 | 后焦距 | feasibility |
| `TOTR` | 总长 | 全程轻约束 |
| `AXCL` | 轴向色差 | IQ 起 |
| `LACL` | 垂轴色差 | IQ 起 |
| `DIMX` | 最大畸变 | field-balance 起 |
| `MNCT` `MNET` `MNEA` `MNEG` `MXSD` `GCOS` | 可制造 | manufacturability |

组态号写到 operand 对应 cell（Python 实现里曾用第 12 列；MATLAB 应通过 `GetCellAt` / `GetOperandCell` 与 Syntax Help 确认，不要猜错列还静默继续）。设完后 `CalculateMeritFunction` 或 `OpenMeritFunctionCalculator` 读总 merit。

---

## 变量释放

每阶段开始：

1. `TheSystem.Tools.RemoveAllVariables();`
2. 按阶段 `MakeSolveVariable`。
3. 变焦：MCE 中 `THIC`（或 profile `mce_variable_operand_types`）各组态 cell 设为 variable。

```matlab
surf.RadiusCell.MakeSolveVariable();
surf.ThicknessCell.MakeSolveVariable();
try
    surf.MaterialCell.MakeSolveVariable();
catch
end
cell = mceOp.GetOperandCell(int32(cfg));
cell.MakeSolveVariable();
```

**手术式控制**：只放开 profile / 计划里列出的表面。禁止「所有半径全变」。收敛失败时缩小变量集（recovery_level++），不要扩大。

定焦无 profile 时的保守默认（与 Python primitives 一致）：

- feasibility：前组半径 + 最后有限面附近 + 一个气隙
- image-quality：内部窗口半径 + 选定厚度
- field-balance：略扩窗口
- manufacturability：缩回关键半径 + 玻璃

---

## 局部优化调用

见 `matlab-zos-api-patterns.md`。记录 `InitialMeritFunction` 与 `CurrentMeritFunction`。`Cycles = OptimizationCycles.Automatic`。

超时：`automation.max_optimization_seconds_per_stage` 仅作软限制；超时仍必须存当前镜头并标记 `accepted=false` 或 `notes` 含 timeout。

---

## 接受 / 拒绝

拒绝并回滚到本阶段起始存盘，若出现：

- 硬约束（最小厚度、气隙、最大口径、像面位置）被破坏
- 镜头类别、变焦比、片数包络被改掉
- 仅中心视场/仅宽端变好
- 玻璃飞出指定 catalog
- 出现未记录的结构改动（增删面）

回滚：`LoadFile(stageStartPath, false)`，提高 recovery_level，减少变量后再试 **同一阶段**。
