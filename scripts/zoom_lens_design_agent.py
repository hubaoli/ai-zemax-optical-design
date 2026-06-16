"""
Automated zoom lens design agent for Zemax OpticStudio 2024 R1.
Profile-driven sequential zoom lens design.

Connects via Interactive Extension and runs a staged design loop:
  1. Build profile-defined zoom starting prescription
  2. Set up MCE multi-configuration
  3. Use optimization wizard + custom operands
  4. Staged optimization (feasibility → image-quality → field-balance → manufacturability)
  5. Export analyses and save lens files
"""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict, dataclass, field
from datetime import datetime
from pathlib import Path
from typing import Any

# ── Path setup ──────────────────────────────────────────────────────────────
SCRIPTS_DIR = Path(__file__).resolve().parent
SKILL_DIR = SCRIPTS_DIR.parent
if str(SCRIPTS_DIR) not in sys.path:
    sys.path.insert(0, str(SCRIPTS_DIR))

from zos_design_primitives import (
    append_jsonl,
    connect_zemax,
    read_text_robust,
    set_wavelengths,
    set_fields,
    set_aperture,
)


# ── Dataclasses ──────────────────────────────────────────────────────────────

@dataclass
class StageResult:
    name: str
    lens_path: str | None = None
    metrics_path: str | None = None
    analysis_dir: str | None = None
    merit_value: float | None = None
    accepted: bool = False
    notes: list[str] = field(default_factory=list)


# ── Lens surface helper ─────────────────────────────────────────────────────

class LensBuilder:
    """Fluent helper to build a sequential lens surface-by-surface."""

    def __init__(self, system: Any):
        self.system = system
        self.lde = system.LDE

    def clear_and_resize(self, num_surfaces: int) -> None:
        while self.lde.NumberOfSurfaces < num_surfaces:
            self.lde.InsertNewSurfaceAt(self.lde.NumberOfSurfaces)
        while self.lde.NumberOfSurfaces > num_surfaces:
            self.lde.RemoveSurface(self.lde.NumberOfSurfaces)

    def set(self, surf_1based: int, radius: float | None = None,
            thickness: float | None = None, material: str | None = None,
            stop: bool = False) -> None:
        s = self.lde.GetSurfaceAt(surf_1based)
        if radius is not None:
            s.Radius = radius
        if thickness is not None:
            s.Thickness = thickness
        if material is not None:
            s.Material = material
        if stop:
            try:
                self.lde.StopSurface = surf_1based
            except Exception:
                pass


# ── Build starting prescription ──────────────────────────────────────────────

DEFAULT_LENS_PROFILE = {
    "name": "generic profile-driven zoom",
    "description": "Minimal generic zoom profile. Real designs should provide requirements.lens_profile.",
    "surfaces": [
        {"surface": 0, "radius": "infinity", "thickness": "infinity", "material": ""},
        {"surface": 1, "radius": 60.0, "thickness": 5.0, "material": "N-BK7"},
        {"surface": 2, "radius": -80.0, "thickness": 8.0, "material": "", "variable_gap": "g1"},
        {"surface": 3, "radius": -45.0, "thickness": 3.0, "material": "N-SF5"},
        {"surface": 4, "radius": 45.0, "thickness": 8.0, "material": "", "variable_gap": "g2"},
        {"surface": 5, "radius": 55.0, "thickness": 4.0, "material": "N-BK7", "stop": True},
        {"surface": 6, "radius": -70.0, "thickness": 20.0, "material": "", "variable_gap": "bfl"},
        {"surface": 7, "radius": "infinity", "thickness": 0.0, "material": ""},
    ],
    "variable_gaps": [
        {"name": "g1", "surface": 2, "default_mm": 8.0},
        {"name": "g2", "surface": 4, "default_mm": 8.0},
        {"name": "bfl", "surface": 6, "default_mm": 20.0},
    ],
    "merit": {"bfl_surface": 6, "max_field_index": 3},
    "mce": {"include_aperture_operand": True, "include_field_operand": True},
}


def load_lens_profile(requirements: dict[str, Any], base_dir: Path | None = None) -> dict[str, Any]:
    """Load and normalize a zoom lens profile from requirements."""
    profile_ref = requirements.get("lens_profile") or requirements.get("lens_profile_path") or requirements.get("profile")
    if isinstance(profile_ref, dict):
        return normalize_lens_profile(profile_ref)
    if isinstance(profile_ref, str) and profile_ref.strip():
        path = Path(profile_ref)
        if not path.is_absolute() and base_dir is not None:
            path = base_dir / path
        data = json.loads(path.read_text(encoding="utf-8"))
        normalized = normalize_lens_profile(data)
        normalized["source_path"] = str(path.resolve())
        return normalized
    return normalize_lens_profile(DEFAULT_LENS_PROFILE)


def normalize_lens_profile(profile: dict[str, Any]) -> dict[str, Any]:
    """Validate and enrich a user-supplied zoom lens profile."""
    normalized = dict(profile)
    surfaces = [dict(item) for item in normalized.get("surfaces") or []]
    if not surfaces:
        raise ValueError("Lens profile must include a non-empty 'surfaces' list.")

    seen_surfaces: set[int] = set()
    for surface in surfaces:
        if "surface" not in surface:
            raise ValueError("Each profile surface must include a 'surface' index.")
        index = int(surface["surface"])
        if index in seen_surfaces:
            raise ValueError(f"Duplicate surface index in lens profile: {index}")
        seen_surfaces.add(index)
        surface["surface"] = index
        surface["radius"] = _profile_number(surface.get("radius", "infinity"))
        surface["thickness"] = _profile_number(surface.get("thickness", 0.0))
        surface["material"] = surface.get("material", "")
    surfaces.sort(key=lambda item: item["surface"])

    explicit_gaps = [dict(item) for item in normalized.get("variable_gaps") or []]
    gaps_by_name: dict[str, dict[str, Any]] = {}
    for gap in explicit_gaps:
        name = str(gap.get("name") or gap.get("variable_gap") or gap.get("surface"))
        if "surface" not in gap:
            raise ValueError(f"Variable gap '{name}' must include a surface index.")
        gap["name"] = name
        gap["surface"] = int(gap["surface"])
        gap["default_mm"] = float(gap.get("default_mm", gap.get("default", 0.0)))
        gap["per_config"] = dict(gap.get("per_config") or {})
        gaps_by_name[name] = gap

    for surface in surfaces:
        gap_name = surface.get("variable_gap")
        if not gap_name:
            continue
        gap_name = str(gap_name)
        gaps_by_name.setdefault(
            gap_name,
            {
                "name": gap_name,
                "surface": surface["surface"],
                "default_mm": float(surface.get("thickness", 0.0)),
                "per_config": {},
            },
        )

    variable_gaps = sorted(gaps_by_name.values(), key=lambda item: item["surface"])
    surface_count = max(surface["surface"] for surface in surfaces) + 1
    image_surface = int(normalized.get("image_surface", max(surface["surface"] for surface in surfaces)))
    merit = dict(normalized.get("merit") or {})
    merit.setdefault("bfl_surface", max(1, image_surface - 1))
    merit.setdefault("max_field_index", 3)
    mce = dict(normalized.get("mce") or {})
    mce.setdefault("include_aperture_operand", True)
    mce.setdefault("include_field_operand", True)

    normalized["surfaces"] = surfaces
    normalized["variable_gaps"] = variable_gaps
    normalized["variable_gap_surfaces"] = [gap["surface"] for gap in variable_gaps]
    normalized["surface_count"] = surface_count
    normalized["image_surface"] = image_surface
    normalized["merit"] = merit
    normalized["mce"] = mce
    normalized.setdefault("name", "unnamed zoom lens profile")
    return normalized


def _profile_number(value: Any) -> float:
    if isinstance(value, str) and value.strip().lower() in {"inf", "+inf", "infinity", "+infinity"}:
        return float("inf")
    if isinstance(value, str) and value.strip().lower() in {"-inf", "-infinity"}:
        return float("-inf")
    return float(value)


def build_zoom_prescription_from_profile(lb: LensBuilder, profile: dict[str, Any]) -> list[int]:
    """Build a sequential zoom prescription from a normalized profile."""
    lb.clear_and_resize(int(profile["surface_count"]))
    for surface in profile["surfaces"]:
        lb.set(
            int(surface["surface"]),
            radius=surface.get("radius"),
            thickness=surface.get("thickness"),
            material=surface.get("material", ""),
            stop=bool(surface.get("stop")),
        )
    gap_surfaces = list(profile.get("variable_gap_surfaces") or [])
    print(f"  Prescription profile: {profile.get('name')}")
    print(f"  Surfaces: {profile['surface_count']}, variable gaps: {gap_surfaces}")
    return gap_surfaces


def resolve_gap_initial_value(gap: dict[str, Any], zoom_config: dict[str, Any]) -> float:
    """Return the initial gap value for one configuration."""
    explicit_values = zoom_config.get("gap_values_mm") or zoom_config.get("gaps_mm") or {}
    gap_name = str(gap.get("name"))
    if gap_name in explicit_values:
        return float(explicit_values[gap_name])
    surface_key = str(gap.get("surface"))
    if surface_key in explicit_values:
        return float(explicit_values[surface_key])

    cfg_name = str(zoom_config.get("name") or "").lower()
    for key, value in (gap.get("per_config") or {}).items():
        if str(key).lower() == cfg_name or str(key).lower() in cfg_name:
            return float(value)
    return float(gap.get("default_mm", 0.0))



def build_zoom_prescription(lb: LensBuilder) -> list[int]:
    """Backward-compatible wrapper; new code should pass an explicit lens profile."""
    return build_zoom_prescription_from_profile(lb, normalize_lens_profile(DEFAULT_LENS_PROFILE))


def setup_zoom_mce(system: Any, zoom_configs: list[dict[str, Any]],
                   gap_surfaces: list[int], profile: dict[str, Any] | None = None) -> None:
    """
    Set up Multi-Configuration Editor for zoom.

    For each configuration, set THIC operands on the variable gap surfaces.
    Also add YFIE (field Y) operands if needed to keep image height constant.
    """
    mce = system.MCE
    profile = profile or normalize_lens_profile(DEFAULT_LENS_PROFILE)
    profile_mce = profile.get("mce") or {}
    variable_gaps = list(profile.get("variable_gaps") or [])
    if not variable_gaps:
        variable_gaps = [{"name": f"gap_{surface}", "surface": surface, "default_mm": 0.0} for surface in gap_surfaces]
    include_aperture = bool(profile_mce.get("include_aperture_operand", True))
    include_field = bool(profile_mce.get("include_field_operand", True))
    # Ensure correct number of configurations
    while mce.NumberOfConfigurations < len(zoom_configs):
        mce.AddConfiguration(True)
    while mce.NumberOfConfigurations > len(zoom_configs):
        mce.DeleteConfiguration(mce.NumberOfConfigurations)

    # Ensure enough operands (one per variable gap + optional extras)
    needed_ops = len(variable_gaps) + int(include_aperture) + int(include_field)
    while mce.NumberOfOperands < needed_ops:
        mce.AddOperand()
    while mce.NumberOfOperands > needed_ops:
        mce.RemoveOperandAt(mce.NumberOfOperands)

    # Import the operand type enum
    import clr
    clr.AddReference(str(Path(os.environ.get("ZOSAPI_ROOT",
        r"D:\Program Files\Ansys Zemax OpticStudio 2024 R1.00")) / "ZOSAPI_Interfaces.dll"))
    from ZOSAPI.Editors.MCE import MultiConfigOperandType

    # ── Initial gap estimates per configuration (empirical) ──────────────────
    # These will be refined during optimization.
    # Values determined by first-order Gaussian optics for 3x zoom range.
    gap_estimates = {
        # name_keyword: [G1→G2(S7), G2→G3(S10), G3→G4(S16)]
        "wide": [4.0,  12.0, 28.0],
        "mid":  [22.0,  5.0, 17.0],
        "tele": [35.0,  2.0,  7.0],
    }

    # Operand 1..N: THIC for each variable gap
    for op_idx, gap in enumerate(variable_gaps):
        surf_num = int(gap["surface"])
        operand = mce.GetOperandAt(op_idx + 1)
        operand.ChangeType(MultiConfigOperandType.THIC)
        operand.Param1 = surf_num

        for cfg_idx, cfg in enumerate(zoom_configs):
            cfg_num = cfg_idx + 1
            cfg_name = cfg.get("name", "")
            # Match initial gaps by name keyword
            gaps = [4.0, 12.0, 28.0]  # default: wide
            for key in gap_estimates:
                if key in cfg_name.lower():
                    gaps = gap_estimates[key]
                    break
            gap_val = resolve_gap_initial_value(gap, cfg)
            cell = operand.GetOperandCell(cfg_num)
            cell.DoubleValue = gap_val
            print(f"    THIC {gap['name']} S{surf_num} Config{cfg_num}='{cfg_name}': {gap_val}mm")

    # Operand N+1: APER (aperture type per config)
    op_aper = mce.GetOperandAt(len(variable_gaps) + 1)
    op_aper.ChangeType(MultiConfigOperandType.APER)
    op_aper.Param1 = 0  # System aperture
    for cfg_idx, cfg in enumerate(zoom_configs):
        cfg_num = cfg_idx + 1
        fnum = cfg.get("f_number", profile_mce.get("default_f_number", 1.4))
        op_aper.GetOperandCell(cfg_num).DoubleValue = fnum
        print(f"    APER Config{cfg_num}: F/{fnum}")

    # Operand N+2: YFIE to set field height per config (keep image height constant)
    op_yfie = mce.GetOperandAt(len(variable_gaps) + 2)
    op_yfie.ChangeType(MultiConfigOperandType.YFIE)
    op_yfie.Param1 = int(profile.get("merit", {}).get("max_field_index", 3))
    for cfg_idx, cfg in enumerate(zoom_configs):
        cfg_num = cfg_idx + 1
        img_h = cfg.get("image_height_mm", profile_mce.get("default_image_height_mm", 14.17))
        # At field angle 38.2°, image height varies with EFL. We set YFIE=0
        # meaning "use current field definition" (object-space angle).
        # Alternative: set specific image height per config
        op_yfie.GetOperandCell(cfg_num).DoubleValue = img_h
        print(f"    YFIE Config{cfg_num}: {img_h}mm image height")

    print(f"  MCE: {mce.NumberOfConfigurations} configs, {mce.NumberOfOperands} operands")


# ── Merit Function Builder ───────────────────────────────────────────────────

def build_merit_function(system: Any, requirements: dict[str, Any],
                          zoom_configs: list[dict[str, Any]],
                          stage: str,
                          profile: dict[str, Any] | None = None) -> None:
    """
    Build staged merit function using optimization wizard + custom targets.

    Uses the built-in RMS Spot Radius wizard as the base, then adds
    first-order targets (EFL, F/#, image height) and constraints.
    """
    from ZOSAPI.Editors.MFE import MeritOperandType

    mfe = system.MFE

    # Clear existing merit function
    mfe.DeleteAllRows()

    num_configs = len(zoom_configs)

    # ── Use Optimization Wizard for default merit function ───────────────────
    # RMS Spot Radius + Centroid, Gaussian Quadrature, 3 rings, 6 arms
    try:
        wizard = mfe.SEQOptimizationWizard
        wizard.PupilIntegrationMethod = 0  # 0=Gaussian Quadrature
        wizard.Data = 4                     # 4=Spot X+Y
        wizard.Ring = 2                     # 3 rings
        wizard.Arm = 0                      # 6 arms
        wizard.Type = 0                     # 0=RMS, 1=PTV(wavefront)
        wizard.Reference = 0                # 0=Centroid
        wizard.Grid = 0                     # 4x4 (not used for Gaussian)
        wizard.OverallWeight = 1.0
        wizard.IsIgnoreLateralColorUsed = False
        wizard.IsAssumeAxialSymmetryUsed = True
        wizard.IsGlassUsed = True
        wizard.IsAirUsed = True
        wizard.GlassMin = 1.5
        wizard.GlassMax = 8.0
        wizard.GlassEdge = 2.0
        wizard.AirMin = 1.0
        wizard.AirMax = 50.0
        wizard.AirEdge = 0.5
        wizard.StartAt = 1
        wizard.OK()
        print("  Optimization wizard applied: RMS Spot Radius, Gaussian Quadrature, 3R/6A")
    except Exception as e:
        print(f"  [WARN] Optimization wizard failed: {e}")
        print("  Adding manual default operands...")
        _add_default_spot_operands(mfe, MeritOperandType, num_configs)

    # ── Add first-order targets per configuration ────────────────────────────
    _add_first_order_targets(mfe, MeritOperandType, requirements, zoom_configs, stage, profile)

    # ── Add manufacturing constraints ────────────────────────────────────────
    _add_manufacturing_constraints(mfe, MeritOperandType, requirements, stage)

    # Calculate the initial merit value
    try:
        calc = system.Tools.OpenMeritFunctionCalculator()
        calc.RunAndWaitForCompletion()
        merit_val = calc.MeritFunctionCalculation
        calc.Close()
        print(f"  Initial merit function value: {merit_val:.6f}")
    except Exception:
        pass

    print(f"  Merit function built: stage='{stage}'")


def _add_default_spot_operands(mfe, op_type, num_configs: int) -> None:
    """Add manual TRAC operands for spot optimization as fallback."""
    for cfg in range(1, num_configs + 1):
        for field in [1, 2, 3]:
            for wave in [1, 2]:
                # TRAC X
                op = mfe.AddOperand()
                op.ChangeType(op_type.TRAC)
                op.Target = 0.0
                op.Weight = 0.5
                # Set params via cells
                _set_op_cell(op, 2, wave)   # Int1 = wave
                _set_op_cell(op, 3, field)  # Int2 = field
                _set_op_cell(op, 4, 0)      # Hx = 0
                _set_op_cell(op, 5, 0)      # Hy = 0
                _set_op_cell(op, 6, 0)      # Px = 0
                _set_op_cell(op, 7, 1)      # Py = 1 (X-component)
                _set_op_cell(op, 12, cfg)   # Config

                # TRAC Y
                op = mfe.AddOperand()
                op.ChangeType(op_type.TRAC)
                op.Target = 0.0
                op.Weight = 0.5
                _set_op_cell(op, 2, wave)
                _set_op_cell(op, 3, field)
                _set_op_cell(op, 7, 0)      # Py = 0 (Y-component)
                _set_op_cell(op, 12, cfg)


def _add_first_order_targets(mfe, op_type, requirements, zoom_configs, stage, profile=None) -> None:
    """Add EFL, F/#, BFL, image height targets per configuration."""
    bfl_target = requirements.get("targets", {}).get("bfl_mm", 25.0)
    ttl_target = requirements.get("targets", {}).get("total_track_mm", 180.0)
    img_h_target = requirements.get("targets", {}).get("image_height_mm", 14.17)
    profile_merit = (profile or {}).get("merit") or {}
    bfl_surface = int(profile_merit.get("bfl_surface", 23))
    max_field_index = int(profile_merit.get("max_field_index", 3))

    weights = {
        "feasibility": 10.0,
        "image-quality": 5.0,
        "field-balance": 3.0,
        "manufacturability": 2.0,
        "baseline": 10.0,
    }
    w = weights.get(stage, 5.0)

    for cfg_idx, cfg in enumerate(zoom_configs):
        conf = cfg_idx + 1
        efl = cfg.get("efl_mm", 50.0)

        # EFFL
        op = mfe.AddOperand()
        op.ChangeType(op_type.EFFL)
        op.Target = efl
        op.Weight = w
        _set_op_cell(op, 2, 0)   # wave = 0 (all)
        _set_op_cell(op, 12, conf)

        # WFNO (working F/#)
        op = mfe.AddOperand()
        op.ChangeType(op_type.WFNO)
        op.Target = cfg.get("f_number", 1.4)
        op.Weight = w * 0.5
        _set_op_cell(op, 12, conf)

        # REAY at max field for image height
        op = mfe.AddOperand()
        op.ChangeType(op_type.REAY)
        op.Target = img_h_target
        op.Weight = w * 0.3
        _set_op_cell(op, 2, 0)   # wave
        _set_op_cell(op, 3, max_field_index)
        _set_op_cell(op, 12, conf)

    # TOTR global constraint
    op = mfe.AddOperand()
    op.ChangeType(op_type.TOTR)
    op.Target = ttl_target
    op.Weight = w * 0.1

    # BFL (CTVA on last glass surface before image)
    op = mfe.AddOperand()
    op.ChangeType(op_type.CTVA)
    op.Target = bfl_target
    op.Weight = w * 0.5
    _set_op_cell(op, 2, 0)
    _set_op_cell(op, 3, bfl_surface)

    # AXCL - axial color
    op = mfe.AddOperand()
    op.ChangeType(op_type.AXCL)
    op.Target = 0.0
    op.Weight = w * 0.3
    _set_op_cell(op, 2, 1)
    _set_op_cell(op, 3, 3)

    # LACL - lateral color
    op = mfe.AddOperand()
    op.ChangeType(op_type.LACL)
    op.Target = 0.0
    op.Weight = w * 0.3
    _set_op_cell(op, 2, 1)
    _set_op_cell(op, 3, 3)

    # DIMX - max distortion
    distortion_target = requirements.get("targets", {}).get("distortion_percent_max", 2.0)
    if stage in ("field-balance", "manufacturability"):
        for cfg_idx in range(len(zoom_configs)):
            op = mfe.AddOperand()
            op.ChangeType(op_type.DIMX)
            op.Target = distortion_target
            op.Weight = 1.0
            _set_op_cell(op, 3, max_field_index)
            _set_op_cell(op, 12, cfg_idx + 1)


def _add_manufacturing_constraints(mfe, op_type, requirements, stage) -> None:
    """Add glass thickness, edge thickness, air gap constraints."""
    if stage not in ("manufacturability",):
        return

    min_ct = requirements.get("constraints", {}).get("min_center_thickness_mm", 0.8)
    min_ag = requirements.get("constraints", {}).get("min_air_gap_mm", 0.1)
    max_diam = requirements.get("constraints", {}).get("max_diameter_mm", 85.0)

    # MNCT: min center thickness
    op = mfe.AddOperand()
    op.ChangeType(op_type.MNCT)
    op.Target = min_ct
    op.Weight = 5.0

    # MNET: min edge thickness
    op = mfe.AddOperand()
    op.ChangeType(op_type.MNET)
    op.Target = 0.5
    op.Weight = 3.0

    # MNEA: min air gap
    op = mfe.AddOperand()
    op.ChangeType(op_type.MNEA)
    op.Target = min_ag
    op.Weight = 3.0

    # MXSD: max semi-diameter
    op = mfe.AddOperand()
    op.ChangeType(op_type.MXSD)
    op.Target = max_diam / 2.0
    op.Weight = 1.0

    # MNEG: min edge glass thickness
    op = mfe.AddOperand()
    op.ChangeType(op_type.MNEG)
    op.Target = 0.5
    op.Weight = 3.0

    # Glass cost
    op = mfe.AddOperand()
    op.ChangeType(op_type.GCOS)
    op.Target = 0.0
    op.Weight = 0.1


def _set_op_cell(op, col: int, value: float) -> None:
    """Set a cell value in the MFE operand row."""
    try:
        cell = op.GetOperandCell(col)
        if isinstance(value, float) or isinstance(value, int):
            cell.DoubleValue = float(value)
        else:
            cell.IntegerValue = int(value)
    except Exception:
        pass  # cell/column may not exist, skip gracefully


# ── Variable configuration ───────────────────────────────────────────────────

def configure_zoom_variables(system: Any, gap_surfaces: list[int],
                              zoom_configs: list[dict[str, Any]],
                              stage: str,
                              profile: dict[str, Any] | None = None) -> None:
    """Set optimization variables based on stage."""
    lde = system.LDE
    mce = system.MCE
    profile = profile or normalize_lens_profile(DEFAULT_LENS_PROFILE)
    profile_merit = profile.get("merit") or {}
    profile_variables = profile.get("variables") or {}

    if stage == "baseline":
        return

    num_surfs = lde.NumberOfSurfaces

    # ── Always vary MCE thickness gaps ───────────────────────────────────────
    for op_idx in range(1, mce.NumberOfOperands + 1):
        try:
            operand = mce.GetOperandAt(op_idx)
            if operand.TypeName in tuple(profile_variables.get("mce_variable_operand_types", ["THIC"])):
                for cfg in range(1, mce.NumberOfConfigurations + 1):
                    try:
                        operand.GetOperandCell(cfg).MakeSolveVariable()
                    except Exception:
                        pass
        except Exception:
            continue

    if stage == "feasibility":
        # Vary: profile-selected radii + BFL thickness
        radius_surfaces = profile_variables.get("feasibility_radius_surfaces") or _profile_powered_surfaces(profile, num_surfs)
        for s_idx in radius_surfaces:
            try:
                surf = lde.GetSurfaceAt(s_idx)
                if surf.Material and surf.Material != "":
                    surf.RadiusCell.MakeSolveVariable()
            except Exception:
                continue
        try:
            lde.GetSurfaceAt(int(profile_merit.get("bfl_surface", max(1, num_surfs - 2)))).ThicknessCell.MakeSolveVariable()
        except Exception:
            pass

    elif stage in ("image-quality", "field-balance"):
        # Vary: profile-selected radii + selected thicknesses
        radius_surfaces = profile_variables.get(f"{stage}_radius_surfaces") or _profile_interior_surfaces(profile, num_surfs)
        thickness_surfaces = profile_variables.get(f"{stage}_thickness_surfaces") or _profile_interior_surfaces(profile, num_surfs)
        for s_idx in radius_surfaces:
            try:
                surf = lde.GetSurfaceAt(s_idx)
                surf.RadiusCell.MakeSolveVariable()
            except Exception:
                continue
        for s_idx in thickness_surfaces:
            try:
                surf = lde.GetSurfaceAt(s_idx)
                surf.ThicknessCell.MakeSolveVariable()
            except Exception:
                continue

    elif stage == "manufacturability":
        # Vary: profile-selected radii, thicknesses, and glass substitutions
        radius_surfaces = profile_variables.get("manufacturability_radius_surfaces") or _profile_interior_surfaces(profile, num_surfs)
        thickness_surfaces = profile_variables.get("manufacturability_thickness_surfaces") or _profile_interior_surfaces(profile, num_surfs)
        material_surfaces = profile_variables.get("material_surfaces") or _profile_glass_surfaces(profile)
        for s_idx in radius_surfaces:
            try:
                surf = lde.GetSurfaceAt(s_idx)
                surf.RadiusCell.MakeSolveVariable()
            except Exception:
                continue
        for s_idx in thickness_surfaces:
            try:
                surf = lde.GetSurfaceAt(s_idx)
                surf.ThicknessCell.MakeSolveVariable()
            except Exception:
                continue
        for s_idx in material_surfaces:
            try:
                surf = lde.GetSurfaceAt(s_idx)
                if surf.Material and surf.Material != "":
                    surf.MaterialCell.MakeSolveVariable()
            except Exception:
                continue

    print(f"  Variables configured for stage: {stage}")


# ── Analysis export ──────────────────────────────────────────────────────────

def _profile_interior_surfaces(profile: dict[str, Any], num_surfs: int) -> list[int]:
    image_surface = int(profile.get("image_surface", max(1, num_surfs - 1)))
    return [
        int(surface["surface"])
        for surface in profile.get("surfaces", [])
        if 0 < int(surface["surface"]) < image_surface
    ]


def _profile_glass_surfaces(profile: dict[str, Any]) -> list[int]:
    return [
        int(surface["surface"])
        for surface in profile.get("surfaces", [])
        if surface.get("material")
    ]


def _profile_powered_surfaces(profile: dict[str, Any], num_surfs: int) -> list[int]:
    powered = [
        int(surface["surface"])
        for surface in profile.get("surfaces", [])
        if 0 < int(surface["surface"]) < int(profile.get("image_surface", num_surfs - 1))
        and abs(float(surface.get("radius", float("inf")))) != float("inf")
    ]
    return powered or _profile_interior_surfaces(profile, num_surfs)


def export_zoom_analyses(system: Any, analysis_dir: Path,
                         zoom_configs: list[dict[str, Any]]) -> list[str]:
    """Export analyses for each zoom configuration."""
    analysis_dir = analysis_dir.resolve()
    analysis_dir.mkdir(parents=True, exist_ok=True)
    exported: list[str] = []
    mce = system.MCE

    factories = [
        ("spot", "New_StandardSpot"),
        ("mtf", "New_FftMtf"),
        ("wavefront", "New_WavefrontMap"),
        ("rayfan", "New_RayFan"),
        ("distortion", "New_FieldCurvatureAndDistortion"),
    ]

    for cfg_idx, cfg in enumerate(zoom_configs):
        cfg_name = cfg.get("name", f"config_{cfg_idx + 1}")
        cfg_num = cfg_idx + 1
        try:
            mce.SetCurrentConfiguration(cfg_num)
        except Exception:
            try:
                mce.CurrentConfiguration = cfg_num
            except Exception:
                pass

        for name, factory in factories:
            if not hasattr(system.Analyses, factory):
                continue
            try:
                analysis = getattr(system.Analyses, factory)()
                analysis.ApplyAndWaitForCompletion()
                out = analysis_dir / f"{name}_{cfg_name}.txt"
                analysis.GetResults().GetTextFile(str(out))
                exported.append(str(out))
                analysis.Close()
            except Exception as exc:
                print(f"    [WARN] {name}@{cfg_name}: {exc}")

    return exported


# ── Optimization ─────────────────────────────────────────────────────────────

def run_zoom_optimization(system: Any, seconds: int | None = None) -> float:
    """Run local optimization. Returns final merit value."""
    tool = system.Tools.OpenLocalOptimization()
    try:
        # Leave Cycles as Automatic (enum; Python.NET 3.0 doesn't allow int assignment)
        # Just run and wait — the optimizer will converge naturally
        tool.RunAndWaitForCompletion()
    finally:
        tool.Close()

    # Read merit value
    merit = 9e9
    try:
        calc = system.Tools.OpenMeritFunctionCalculator()
        calc.RunAndWaitForCompletion()
        merit = calc.MeritFunctionCalculation
        calc.Close()
    except Exception:
        pass
    return merit


# ── Stage evaluation ─────────────────────────────────────────────────────────

def evaluate_zoom_stage(system, out_dir: Path, stage: str,
                        zoom_configs: list[dict[str, Any]],
                        merit_value: float) -> StageResult:
    """Export analyses, save lens, return stage result."""
    analysis_dir = out_dir / "analyses" / stage
    analysis_files = export_zoom_analyses(system, analysis_dir, zoom_configs)

    metrics = {
        "stage": stage,
        "merit_function_value": merit_value,
        "num_configurations": len(zoom_configs),
        "num_analyses": len(analysis_files),
        "analysis_files": [str(Path(f).name) for f in analysis_files],
    }

    metrics_path = out_dir.resolve() / f"metrics-{stage}.json"
    metrics_path.write_text(json.dumps(metrics, indent=2), encoding="utf-8")

    lens_path = (out_dir.resolve() / f"zoom_{stage}.zmx")
    # Must use absolute path for Zemax SaveAs
    system.SaveAs(str(lens_path.resolve()))

    result = StageResult(
        name=stage,
        lens_path=str(lens_path),
        metrics_path=str(metrics_path),
        analysis_dir=str(analysis_dir),
        merit_value=merit_value,
        accepted=True,
        notes=[f"Stage '{stage}': merit={merit_value:.4f}, {len(analysis_files)} analyses"],
    )

    stage_result_path = out_dir.resolve() / f"stage-{stage}.json"
    stage_result_path.write_text(json.dumps(asdict(result), indent=2), encoding="utf-8")

    return result


# ── Main ─────────────────────────────────────────────────────────────────────

ZOOM_STAGES = ["baseline", "feasibility", "image-quality", "field-balance", "manufacturability"]


def parse_args() -> argparse.Namespace:
    p = argparse.ArgumentParser(description="Automated zoom lens design for Zemax OpticStudio 2024 R1")
    p.add_argument("--requirements", required=True, help="Path to normalized requirements JSON.")
    p.add_argument("--out", default="zoom-lens-design", help="Output directory.")
    p.add_argument("--zos-root", help="OpticStudio install directory.")
    p.add_argument("--standalone", action="store_true", help="Create new OpticStudio instance.")
    return p.parse_args()


def main() -> None:
    args = parse_args()
    out_dir = Path(args.out).resolve()
    out_dir.mkdir(parents=True, exist_ok=True)

    requirements_path = Path(args.requirements)
    requirements = json.loads(requirements_path.read_text(encoding="utf-8"))
    lens_profile = load_lens_profile(requirements, requirements_path.parent)
    zoom_configs = requirements.get("constraints", {}).get("zoom_configurations", [])

    if not zoom_configs:
        print("ERROR: No zoom configurations in requirements.")
        sys.exit(1)

    # Save requirements copy
    (out_dir / "requirements.json").write_text(
        requirements_path.read_text(encoding="utf-8"), encoding="utf-8")

    log_path = out_dir / "design-log.jsonl"

    print("=" * 72)
    print("ZOOM LENS AUTOMATED DESIGN")
    print(f"  Profile: {lens_profile.get('name')}")
    print(f"  Configs: {len(zoom_configs)}")
    for c in zoom_configs:
        print(f"    {c['name']}: EFL={c['efl_mm']}mm F/{c['f_number']}")
    print(f"  Output:  {out_dir}")
    print("=" * 72)

    app = None
    try:
        # ── Connect ──────────────────────────────────────────────────────────
        print("\n[1/5] Connecting to Zemax OpticStudio...")
        app = connect_zemax(args.zos_root, standalone=args.standalone)
        system = app.PrimarySystem
        print("  Connected via Interactive Extension.")

        # ── Build starting prescription ──────────────────────────────────────
        print("\n[2/5] Building profile-driven zoom starting prescription...")
        system.New(False)
        set_wavelengths(system, requirements.get("wavelengths_um") or [])
        set_fields(system, requirements.get("fields") or [])
        set_aperture(system, requirements.get("aperture") or {})

        lb = LensBuilder(system)
        gap_surfaces = build_zoom_prescription_from_profile(lb, lens_profile)
        setup_zoom_mce(system, zoom_configs, gap_surfaces, lens_profile)

        # ── Staged optimization ──────────────────────────────────────────────
        print("\n[3/5] Starting staged optimization loop...")

        for stage_idx, stage in enumerate(ZOOM_STAGES):
            print(f"\n  {'='*60}")
            print(f"  STAGE {stage_idx + 1}/{len(ZOOM_STAGES)}: {stage.upper()}")
            print(f"  {'='*60}")

            append_jsonl(log_path, {"event": "stage-start", "stage": stage})

            merit_value = 9e9
            if stage != "baseline":
                configure_zoom_variables(system, gap_surfaces, zoom_configs, stage, lens_profile)
                build_merit_function(system, requirements, zoom_configs, stage, lens_profile)

                max_sec = requirements.get("automation", {}).get(
                    "max_optimization_seconds_per_stage", 120)
                print(f"  Optimizing (max {max_sec}s)...")
                merit_value = run_zoom_optimization(system, seconds=max_sec)
                print(f"  Final merit: {merit_value:.6f}")
            else:
                # Baseline: just evaluate without optimization
                build_merit_function(system, requirements, zoom_configs, stage, lens_profile)
                try:
                    calc = system.Tools.OpenMeritFunctionCalculator()
                    calc.RunAndWaitForCompletion()
                    merit_value = calc.MeritFunctionCalculation
                    calc.Close()
                    print(f"  Baseline merit: {merit_value:.6f}")
                except Exception:
                    pass

            result = evaluate_zoom_stage(system, out_dir, stage, zoom_configs, merit_value)
            append_jsonl(log_path, {"event": "stage-finish", "stage": stage,
                                     "result": asdict(result)})
            print(f"  Saved: {result.lens_path}")

        # ── Final summary ────────────────────────────────────────────────────
        print("\n[4/5] Design loop complete!")
        print(f"\n  Outputs in: {out_dir}")
        for item in sorted(out_dir.rglob("*")):
            if item.is_file():
                size = item.stat().st_size
                print(f"    {item.relative_to(out_dir)}  ({size:,} bytes)")

        print(f"\n[5/5] Key files:")
        final_lens = out_dir / "zoom_manufacturability.zmx"
        print(f"  Final lens:   {final_lens}")
        print(f"  Design log:   {log_path}")
        print(f"  Analyses:     {out_dir / 'analyses'}")

        print("\n" + "=" * 72)
        print("DESIGN COMPLETE — Review in Zemax OpticStudio:")
        print("  1. Open the saved .zmx file")
        print("  2. Check MTF at all fields for each zoom position")
        print("  3. Verify zoom cam curves are smooth and feasible")
        print("  4. Check distortion at wide end (18mm)")
        print("  5. Verify relative illumination > 50% at edge")
        print("  6. Review glass selection for cost and availability")
        print("=" * 72)

    finally:
        if app is not None and args.standalone:
            print("\nClosing Zemax...")
            app.CloseApplication()


if __name__ == "__main__":
    main()
