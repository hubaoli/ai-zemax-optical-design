from __future__ import annotations

import importlib.util
import json
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MODULE_PATH = ROOT / "scripts" / "zoom_lens_design_agent.py"


def load_zoom_agent():
    spec = importlib.util.spec_from_file_location("zoom_lens_design_agent_under_test", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


class FakeSurface:
    def __init__(self):
        self.Radius = None
        self.Thickness = None
        self.Material = None


class FakeLDE:
    def __init__(self):
        self.NumberOfSurfaces = 1
        self.surfaces = {0: FakeSurface(), 1: FakeSurface()}
        self.StopSurface = None

    def InsertNewSurfaceAt(self, index):
        self.NumberOfSurfaces += 1
        self.surfaces[self.NumberOfSurfaces - 1] = FakeSurface()

    def RemoveSurface(self, index):
        self.NumberOfSurfaces -= 1
        self.surfaces.pop(index, None)

    def GetSurfaceAt(self, index):
        self.surfaces.setdefault(index, FakeSurface())
        return self.surfaces[index]


class FakeSystem:
    def __init__(self):
        self.LDE = FakeLDE()


class ZoomLensProfileTest(unittest.TestCase):
    def test_load_lens_profile_from_requirements_path(self):
        zoom_agent = load_zoom_agent()
        profile = {
            "name": "custom 2 group zoom",
            "surfaces": [
                {"surface": 0, "radius": "infinity", "thickness": "infinity"},
                {"surface": 1, "radius": 40.0, "thickness": 4.0, "material": "N-BK7"},
                {"surface": 2, "radius": -40.0, "thickness": 10.0, "material": "", "variable_gap": "front_to_variator"},
                {"surface": 3, "radius": -30.0, "thickness": 3.0, "material": "N-SF5", "stop": True},
                {"surface": 4, "radius": "infinity", "thickness": 0.0, "material": ""},
            ],
            "variable_gaps": [
                {
                    "name": "front_to_variator",
                    "surface": 2,
                    "default_mm": 10.0,
                    "per_config": {"wide": 8.0, "tele": 16.0},
                }
            ],
            "merit": {"bfl_surface": 2, "max_field_index": 2},
        }
        with tempfile.TemporaryDirectory() as tmp:
            profile_path = Path(tmp) / "profile.json"
            profile_path.write_text(json.dumps(profile), encoding="utf-8")

            loaded = zoom_agent.load_lens_profile({"lens_profile": str(profile_path)}, Path(tmp))

        self.assertEqual(loaded["name"], "custom 2 group zoom")
        self.assertEqual(loaded["surface_count"], 5)
        self.assertEqual(loaded["image_surface"], 4)
        self.assertEqual(loaded["variable_gap_surfaces"], [2])
        self.assertEqual(loaded["merit"]["bfl_surface"], 2)

    def test_build_zoom_prescription_from_profile_uses_profile_surfaces_and_stop(self):
        zoom_agent = load_zoom_agent()
        system = FakeSystem()
        lb = zoom_agent.LensBuilder(system)
        profile = zoom_agent.normalize_lens_profile(
            {
                "name": "surface driven zoom",
                "surfaces": [
                    {"surface": 0, "radius": "infinity", "thickness": "infinity"},
                    {"surface": 1, "radius": 25.0, "thickness": 2.0, "material": "N-BK7"},
                    {"surface": 2, "radius": -30.0, "thickness": 5.0, "material": "", "variable_gap": "g1"},
                    {"surface": 3, "radius": "infinity", "thickness": 1.0, "material": "", "stop": True},
                    {"surface": 4, "radius": "infinity", "thickness": 0.0, "material": ""},
                ],
                "variable_gaps": [{"name": "g1", "surface": 2, "default_mm": 5.0}],
            }
        )

        gap_surfaces = zoom_agent.build_zoom_prescription_from_profile(lb, profile)

        self.assertEqual(gap_surfaces, [2])
        self.assertEqual(system.LDE.NumberOfSurfaces, 5)
        self.assertEqual(system.LDE.GetSurfaceAt(1).Radius, 25.0)
        self.assertEqual(system.LDE.GetSurfaceAt(1).Material, "N-BK7")
        self.assertEqual(system.LDE.GetSurfaceAt(2).Thickness, 5.0)
        self.assertEqual(system.LDE.StopSurface, 3)

    def test_gap_initialization_uses_explicit_configuration_values_before_name_keywords(self):
        zoom_agent = load_zoom_agent()
        profile = zoom_agent.normalize_lens_profile(
            {
                "surfaces": [
                    {"surface": 0, "radius": "infinity", "thickness": "infinity"},
                    {"surface": 1, "radius": 30.0, "thickness": 2.0, "material": "N-BK7"},
                    {"surface": 2, "radius": -30.0, "thickness": 5.0, "material": "", "variable_gap": "g1"},
                    {"surface": 3, "radius": "infinity", "thickness": 0.0, "material": ""},
                ],
                "variable_gaps": [
                    {"name": "g1", "surface": 2, "default_mm": 5.0, "per_config": {"wide": 4.0, "tele": 12.0}}
                ],
            }
        )

        explicit = zoom_agent.resolve_gap_initial_value(
            profile["variable_gaps"][0],
            {"name": "wide", "gap_values_mm": {"g1": 9.5}},
        )
        keyword = zoom_agent.resolve_gap_initial_value(profile["variable_gaps"][0], {"name": "tele"})
        fallback = zoom_agent.resolve_gap_initial_value(profile["variable_gaps"][0], {"name": "unknown"})

        self.assertEqual(explicit, 9.5)
        self.assertEqual(keyword, 12.0)
        self.assertEqual(fallback, 5.0)


if __name__ == "__main__":
    unittest.main()
