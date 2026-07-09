# AI Zemax Optical Design

Automated optical design skill for **Claude Code and Codex** — drives **Ansys Zemax OpticStudio** through ZOS-API to turn optical requirements into executable, multi-stage design loops.

[![version](https://img.shields.io/badge/version-1.3.0-blue)](https://github.com/Jerry-del975/ai-zemax-optical-design)
[![license](https://img.shields.io/badge/license-MIT-green)](LICENSE)

---

## What's New in v1.3.0

- **Profile-driven zoom lens design** — `zoom_lens_design_agent.py` is no longer hardcoded to APS-C 18-55mm. The complete starting prescription (surfaces, materials, variable gaps, MCE setup, optimization variables per stage) is defined in a standalone JSON profile. Swap profiles to design different zoom systems without touching Python code.
- **Zoom lens profile schema** — new `lens_profile` field in requirements references a JSON profile file or inline object. Profiles define every surface, variable gap, glass material, stop location, merit function parameters, and per-stage variable release lists. See `examples/profiles/apsc_18_55_f14_zoom_profile.json` for the first example and `references/requirements-schema.md` for the schema.
- **Per-configuration gap initialization** — `resolve_gap_initial_value()` supports three priority levels: explicit `gap_values_mm` in each zoom configuration → per-config name matching in `variable_gaps.per_config` → `default_mm` fallback. No more array-index-based gap lookup.
- **Surgical variable control** — each optimization stage uses profile-defined surface lists (`feasibility_radius_surfaces`, `image-quality_radius_surfaces`, `material_surfaces`, etc.) instead of varying every surface. This prevents over-parameterization and accelerates convergence.
- **`InstanceId` parameterization** — PowerShell connection scripts now accept `-InstanceId` (default 1) instead of hardcoded `ConnectAsExtension(0)`.
- **pythonnet fallback singlet script** — new `scripts/design_single_lens_pythonnet.py` is a lightweight alternative that connects directly via `clr` / pythonnet without ZOSPy. Intended as a fallback for environments where ZOSPy cannot be installed; the primary connection layer for all design agents remains ZOSPy.
- **Zoom lens profile unit tests** — `tests/test_zoom_lens_profile.py` validates profile loading from path, prescription building with stop surfaces, and gap initialization priority logic.

## What's New in v1.2.0

- **Zoom lens design agent** — new `scripts/zoom_lens_design_agent.py` for multi-configuration zoom systems with automatic MCE setup, staged optimization, and per-configuration analysis export.
- **APS-C 18-55mm F/1.4 example** — complete zoom requirements and 4-group starting prescription with 3× zoom ratio, constant F/1.4 aperture.
- **Hardened ZOS-API patterns** — fixed real-world API mismatches discovered during intensive testing: `MultiConfigOperandType` enum usage, MCE `AddConfiguration` signatures, optimization wizard property names, `LDE.StopSurface`, Python.NET 3.0 enum handling, and more.
- **Automated analysis export** — per-configuration spot, MTF, wavefront, ray fan, and distortion analyses for every stage.
- **Extended merit function builder** — built-in optimization wizard integration plus first-order targets (EFFL, WFNO, REAY, AXCL, LACL, DIMX) and manufacturing constraints (MNCT, MNET, MNEA, MXSD, MNEG, GCOS).

## What's New in v1.1.0

- **ZOSPy integration** — connection layer uses [ZOSPy](https://github.com/MREYE-LUMC/ZOSPy) for automatic version discovery across OpticStudio v20.3 through v26+. A standalone pythonnet fallback script is also available for environments where ZOSPy cannot be installed.
- **Multi-version support** — OpticStudio v20.3 through v26+.
- **Dual-mode connection** — Interactive Extension (recommended) and Standalone.

---

## Installation

```bash
# Clone the repo
git clone https://github.com/Jerry-del975/ai-zemax-optical-design.git
cd ai-zemax-optical-design

# Install Python dependencies
pip install zospy pythonnet

# Install as Claude Code skill (default)
npm install

# Or install as Codex skill
npm run install:codex
```

The postinstall script deploys the skill to `~/.claude/skills/ai-zemax-optical-design/` by default. To install for Codex, run `npm run install:codex`; this deploys to `${CODEX_HOME:-~/.codex}/skills/ai-zemax-optical-design/`. Restart the target agent after installation.

### Prerequisites

| Component | Requirement |
|-----------|-------------|
| **OS** | Windows 10/11 |
| **OpticStudio** | 2024 R1 (tested), v20.3+ (via ZOSPy) |
| **Python** | 3.10+ |
| **Python packages** | `zospy>=2.1` (primary connection, multi-version auto-discovery), `pythonnet` (underlying .NET bridge, also used as fallback when ZOSPy is unavailable) |
| **Claude Code or Codex** | latest |

---

## Quickstart

### 1. Smoke test connection

Make sure OpticStudio is open, then:

```bash
python scripts/connection_smoke_test.py
# Expected: "Connected: yes"
```

### 2. Design a lens

**Simple prime lens:**
```bash
python scripts/automated_design_agent.py \
  --requirements examples/minimal_imaging_requirements.json \
  --out output/my-design
```

**Zoom lens (APS-C 18-55mm F/1.4):**
```bash
python scripts/zoom_lens_design_agent.py \
  --requirements examples/apsc_18-55_f1.4_zoom_requirements.json \
  --out output/aps-c-zoom
```

**Custom zoom lens (your own profile):**
```bash
# 1. Create a profile JSON (copy examples/profiles/ as starting point)
# 2. Point requirements.lens_profile to your profile
python scripts/zoom_lens_design_agent.py \
  --requirements my_zoom_requirements.json \
  --out output/my-zoom-design
```

### 3. Review results

```
output/aps-c-zoom/
├── zoom_baseline.zmx          ← Baseline lens (before optimization)
├── zoom_feasibility.zmx       ← After feasibility stage
├── zoom_image-quality.zmx     ← After image quality optimization
├── zoom_field-balance.zmx     ← After field balancing
├── zoom_manufacturability.zmx ← Final lens (all stages)
├── design-log.jsonl           ← Machine-readable event log
├── metrics-*.json             ← Per-stage merit values
├── requirements.json          ← Normalized requirements (copy)
└── analyses/
    ├── baseline/              ← 5 analyses × 3 configurations
    ├── feasibility/
    ├── image-quality/
    ├── field-balance/
    └── manufacturability/
```

---

## What It Does

This skill turns Claude Code or Codex into a Zemax automation agent:

1. **Parse requirements** — normalize optical specs from JSON or existing `.zmx` / `.zos` / `.zar` files
2. **Build or load models** — create sequential starting prescriptions (prime or zoom), or adapt existing designs
3. **Setup multi-configuration** — automatic MCE operand setup for zoom systems with variable air gaps
4. **Run baseline analyses** — spot diagrams, FFT MTF, wavefront maps, ray fans, field curvature/distortion
5. **Stage optimization** — feasibility → image quality → field balance → manufacturability
6. **Export everything** — versioned lens files, analysis text exports, metrics JSON, and design logs

---

## Project Structure

```
├── SKILL.md                              # Skill definition (loaded by Claude Code or Codex)
├── README.md
├── package.json
├── install.js                            # Installer: deploys skill to ~/.claude/skills/ or ~/.codex/skills/
│
├── scripts/
│   ├── zos_design_primitives.py          # Core: ZOSPy connection, analysis, optimization, save
│   ├── automated_design_agent.py         # Prime lens design controller (ZOSPy)
│   ├── zoom_lens_design_agent.py         # ★ Profile-driven zoom design controller (ZOSPy)
│   ├── design_single_lens_pythonnet.py   # ★ Lightweight pythonnet fallback singlet (no ZOSPy)
│   ├── connection_smoke_test.ps1         # PowerShell ZOS-API health check
│   ├── connection_smoke_test.py          # Python ZOS-API health check (ZOSPy)
│   └── design_single_lens_interactive.ps1
│
├── references/
│   ├── requirements-schema.md            # Normalized input schema
│   ├── merit-function.md                 # Staged merit-function rules
│   ├── result-parsing.md                 # Analysis export & logging rules
│   └── zos-api-patterns.md               # ZOS-API 2024 R1 reference
│
├── examples/
│   ├── profiles/
│   │   └── apsc_18_55_f14_zoom_profile.json  # ★ APS-C 4-group zoom profile (new)
│   ├── minimal_imaging_requirements.json
│   ├── apsc_18-55_f1.4_zoom_requirements.json
│   └── seeded_complex_zoom_requirements.json
│
├── tests/
│   ├── test_zos_design_primitives.py
│   ├── test_automated_design_agent.py
│   ├── test_requirements_schema.py
│   └── test_zoom_lens_profile.py         # ★ Profile loading & gap init tests (new)
│
└── output/                               # ★ Design outputs (gitignored)
```

---

## Supported Design Types

| Type | Agent | Connection | Features |
|------|-------|------------|----------|
| Prime lens | `automated_design_agent.py` | ZOSPy (default) | Single-config, EFFL/BFL/F# targets |
| Zoom lens | `zoom_lens_design_agent.py` | ZOSPy (default) | JSON profile-driven, MCE multi-config, variable air gaps, per-config EFL |
| Seed-based | `automated_design_agent.py` | ZOSPy (default) | Load `.zmx` as starting point, adapt to targets |
| Singlet (fallback) | `design_single_lens_pythonnet.py` | pythonnet direct | No ZOSPy dependency; lightweight verification |

---

## Optimization Stages

| Stage | What It Does | Variables |
|-------|-------------|-----------|
| **Baseline** | Export analyses without optimization | None |
| **Feasibility** | Hit EFL, F/#, BFL, image height targets | MCE gaps, BFL, profile-defined feasibility radii |
| **Image Quality** | Minimize RMS spot, wavefront, chromatic error | Profile-defined radii + thicknesses |
| **Field Balance** | Equalize performance across fields/configs | Full profile-defined radii + thicknesses |
| **Manufacturability** | Enforce edge thickness, glass constraints | Profile-defined radii + thicknesses + glass substitutions |

---

## Zoom Lens Profile System (v1.3)

The zoom agent is now fully profile-driven. Instead of a hardcoded prescription, swap a JSON file to design any zoom lens.

```json
{
  "name": "my zoom profile",
  "image_surface": 12,
  "surfaces": [
    {"surface": 1, "radius": 60.0, "thickness": 5.0, "material": "N-BK7"},
    {"surface": 2, "radius": -80.0, "thickness": 8.0, "material": "", "variable_gap": "g1"},
    {"surface": 5, "radius": 55.0, "thickness": 4.0, "material": "N-BK7", "stop": true}
  ],
  "variable_gaps": [
    {"name": "g1", "surface": 2, "default_mm": 8.0, "per_config": {"wide": 6.0, "tele": 14.0}}
  ],
  "merit": {"bfl_surface": 11, "max_field_index": 3},
  "variables": {
    "feasibility_radius_surfaces": [1, 3, 5],
    "image-quality_radius_surfaces": [1, 2, 3, 4, 5],
    "image-quality_thickness_surfaces": [2, 4, 7],
    "material_surfaces": [1, 3, 5]
  }
}
```

Key profile fields:

| Section | Purpose |
|---------|---------|
| `surfaces` | Complete prescription — radius, thickness, material, stop flag, group label, `variable_gap` tag |
| `variable_gaps` | Which gaps vary with zoom position, default values, and per-configuration overrides |
| `merit` | BFL surface reference and max field index for merit function construction |
| `mce` | Multi-Configuration Editor settings (aperture/field operand inclusion) |
| `variables` | Per-stage surface lists controlling exactly which radii, thicknesses, and materials are released |

Each zoom configuration can override initial gap values via `gap_values_mm` or `per_config` name matching. See `examples/profiles/apsc_18_55_f14_zoom_profile.json` for a complete 4-group 24-surface example.

---

## Connection

### Default: ZOSPy (multi-version auto-discovery)

All design agents use ZOSPy as the primary connection layer. ZOSPy automatically discovers your OpticStudio installation (v20.3 through v26+), loads the correct ZOSAPI DLLs, and returns a ready-to-use application object. No hardcoded paths, no version-specific configuration.

```python
from zos_design_primitives import connect_zemax

# Interactive Extension (OpticStudio must be open — recommended)
app = connect_zemax(standalone=False)

# Standalone (creates new OpticStudio instance)
app = connect_zemax(standalone=True)

system = app.PrimarySystem
```

### Fallback: pythonnet direct connection

When ZOSPy cannot be installed (air-gapped environments, dependency conflicts), `design_single_lens_pythonnet.py` provides a lightweight fallback that loads the ZOSAPI DLLs directly via `clr.AddReference`. This requires manually specifying the OpticStudio install path via `--zos-root` and only supports a single version at a time.

```bash
python scripts/design_single_lens_pythonnet.py \
  --zos-root "D:\Program Files\Ansys Zemax OpticStudio 2024 R1.00" \
  --out output/singlet
```

The two main design agents (`automated_design_agent.py` and `zoom_lens_design_agent.py`) **always use ZOSPy** — there is no scenario where they silently fall back to pythonnet. The pythonnet path exists only in the standalone singlet script for environments that explicitly choose it.

---

## Known Limitations

- **MCE operand API** — Python.NET 3.0 has limited enum-to-int conversion; MCE operand types must use `MultiConfigOperandType` enum values explicitly.
- **Chinese paths** — OpticStudio `SaveAs` requires absolute paths; relative paths may silently fail with non-ASCII directory names.
- **Optimization wizard** — properties use `OK()` (uppercase), `Ring`/`Arm`/`Data` (singular), `PupilIntegrationMethod` (full name) — not the intuitive names.
- **Merit function access** — use `system.MFE` directly, not `system.Tools.OpenMeritFunction()`.
- **Stop surface** — set via `system.LDE.StopSurface = N`, not `MakeSurfaceStop()`.

---

## Upgrading

```bash
# Remove old Claude Code skill
rm -rf ~/.claude/skills/ai-zemax-optical-design

# Or remove old Codex skill
rm -rf ~/.codex/skills/ai-zemax-optical-design

# Pull latest
cd ai-zemax-optical-design
git pull origin master
npm install
```

---

## License

MIT © [Jerry](https://github.com/Jerry-del975)
