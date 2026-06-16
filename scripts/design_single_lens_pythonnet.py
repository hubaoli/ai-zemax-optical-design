"""Create and optimize a simple singlet through ZOS-API using pythonnet."""

from __future__ import annotations

import argparse
import json
from datetime import datetime
from pathlib import Path
from typing import Any


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--zos-root", default=r"D:\Program Files\Ansys Zemax OpticStudio 2024 R1.00")
    parser.add_argument("--instance-id", type=int, default=1)
    parser.add_argument("--out", default=r"C:\tmp\zemax-single-lens-design")
    parser.add_argument("--f-number", type=float, default=4.0)
    parser.add_argument("--field-deg", type=float, default=5.0)
    parser.add_argument("--efl-mm", type=float, default=50.0)
    return parser.parse_args()


def connect(zos_root: str, instance_id: int):
    import clr  # type: ignore

    root = Path(zos_root)
    clr.AddReference(str(root / "ZOSAPI_NetHelper.dll"))
    import ZOSAPI_NetHelper  # type: ignore

    ZOSAPI_NetHelper.ZOSAPI_Initializer.Initialize(str(root))
    clr.AddReference(str(root / "ZOSAPI_Interfaces.dll"))
    clr.AddReference(str(root / "ZOSAPI.dll"))

    import ZOSAPI  # type: ignore

    connection = ZOSAPI.ZOSAPI_Connection()
    app = connection.ConnectAsExtension(instance_id)
    if app is None:
        raise RuntimeError(f"ConnectAsExtension({instance_id}) returned null.")
    if not app.IsValidLicenseForAPI:
        raise RuntimeError("Connected to OpticStudio, but IsValidLicenseForAPI is false.")
    if app.PrimarySystem is None:
        raise RuntimeError("Connected to OpticStudio, but PrimarySystem is null.")
    return app


def append_jsonl(path: Path, event: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    payload = {"time": datetime.now().isoformat(timespec="seconds"), **event}
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(payload, ensure_ascii=False) + "\n")


def configure_system(system, f_number: float, field_deg: float) -> None:
    system.New(False)
    try:
        system.SystemData.Aperture.ApertureValue = f_number
    except Exception:
        pass

    wavelengths = system.SystemData.Wavelengths
    while wavelengths.NumberOfWavelengths > 1:
        wavelengths.RemoveWavelength(wavelengths.NumberOfWavelengths)
    wavelengths.GetWavelength(1).Wavelength = 0.5875618
    wavelengths.GetWavelength(1).Weight = 1.0
    wavelengths.AddWavelength(0.4861327, 1.0)
    wavelengths.AddWavelength(0.6562725, 1.0)

    fields = system.SystemData.Fields
    while fields.NumberOfFields > 1:
        fields.RemoveField(fields.NumberOfFields)
    f1 = fields.GetField(1)
    f1.X = 0.0
    f1.Y = 0.0
    f1.Weight = 1.0
    fields.AddField(0.0, field_deg, 1.0)


def build_singlet(system) -> None:
    lde = system.LDE
    while lde.NumberOfSurfaces < 5:
        lde.InsertNewSurfaceAt(max(1, lde.NumberOfSurfaces - 1))

    try:
        lde.StopSurface = 1
    except Exception:
        pass

    stop = lde.GetSurfaceAt(1)
    front = lde.GetSurfaceAt(2)
    back = lde.GetSurfaceAt(3)
    image = lde.GetSurfaceAt(lde.NumberOfSurfaces - 1)

    stop.Thickness = 0.0
    front.Radius = 50.0
    front.Thickness = 5.0
    front.Material = "N-BK7"
    back.Radius = -50.0
    back.Thickness = 45.0
    back.Material = ""
    try:
        image.Radius = float("inf")
        image.Thickness = 0.0
    except Exception:
        pass

    for surface, variable_thickness in ((front, False), (back, True)):
        try:
            surface.RadiusCell.MakeSolveVariable()
        except Exception:
            pass
        if variable_thickness:
            try:
                surface.ThicknessCell.MakeSolveVariable()
            except Exception:
                pass


def build_merit_function(system, efl_mm: float) -> None:
    from ZOSAPI.Editors.MFE import MeritOperandType  # type: ignore

    mfe = system.MFE
    try:
        mfe.DeleteAllRows()
    except Exception:
        pass

    try:
        wizard = mfe.SEQOptimizationWizard
        wizard.Data = 4
        wizard.Type = 0
        wizard.Reference = 0
        wizard.Ring = 2
        wizard.Arm = 0
        wizard.OverallWeight = 1.0
        wizard.OK()
    except Exception:
        pass

    op = mfe.AddOperand()
    op.ChangeType(MeritOperandType.EFFL)
    op.Target = efl_mm
    op.Weight = 10.0


def run_optimization(system) -> str:
    try:
        opt = system.Tools.OpenLocalOptimization()
        try:
            opt.RunAndWaitForCompletion()
        finally:
            opt.Close()
        return "completed"
    except Exception as exc:
        return f"error: {exc}"


def export_analysis(system, analysis_dir: Path, factory: str, name: str) -> dict[str, Any]:
    analysis_dir.mkdir(parents=True, exist_ok=True)
    if not hasattr(system.Analyses, factory):
        return {"name": name, "status": "missing_factory", "file": None}
    analysis = getattr(system.Analyses, factory)()
    try:
        analysis.ApplyAndWaitForCompletion()
        out = analysis_dir / f"{name}.txt"
        analysis.GetResults().GetTextFile(str(out))
        return {"name": name, "status": "exported", "file": str(out)}
    except Exception as exc:
        return {"name": name, "status": "error", "error": str(exc), "file": None}
    finally:
        try:
            analysis.Close()
        except Exception:
            pass


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out)
    analysis_dir = out_dir / "analyses"
    out_dir.mkdir(parents=True, exist_ok=True)
    log_path = out_dir / "design-log.jsonl"

    app = connect(args.zos_root, args.instance_id)
    system = app.PrimarySystem

    append_jsonl(log_path, {"event": "single_lens_start", "instance_id": args.instance_id})
    configure_system(system, args.f_number, args.field_deg)
    build_singlet(system)

    before_path = out_dir / "single-lens-before-optimization.zmx"
    system.SaveAs(str(before_path.resolve()))

    build_merit_function(system, args.efl_mm)
    optimization_status = run_optimization(system)

    after_path = out_dir / "single-lens-after-optimization.zmx"
    system.SaveAs(str(after_path.resolve()))

    analyses = [
        export_analysis(system, analysis_dir, "New_StandardSpot", "spot"),
        export_analysis(system, analysis_dir, "New_FftMtf", "mtf"),
        export_analysis(system, analysis_dir, "New_RayFan", "rayfan"),
        export_analysis(system, analysis_dir, "New_FieldCurvatureAndDistortion", "distortion"),
    ]
    summary = {
        "event": "single_lens_finish",
        "before_lens": str(before_path.resolve()),
        "after_lens": str(after_path.resolve()),
        "optimization_status": optimization_status,
        "analyses": analyses,
    }
    append_jsonl(log_path, summary)
    print(json.dumps(summary, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
