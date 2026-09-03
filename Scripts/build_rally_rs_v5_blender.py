#!/usr/bin/env python3
"""Build the project-original Rally RS revision 5 vehicle with Blender.

Run with Blender 4.5 LTS or newer:
  blender --background --factory-startup --python Scripts/build_rally_rs_v5_blender.py -- <output-dir>

The vehicle uses an independent short-wheelbase body loft and writes an editable
Blender source, Y-up USDA, studio preview, and neutral-white presentation source.
"""

from __future__ import annotations

import math
import pathlib
import sys

import bpy

sys.path.insert(0, str(pathlib.Path(__file__).resolve().parent))

from build_gt_racer_v5_blender import (
    add_box,
    add_bucket_seat,
    add_cylinder,
    add_torus,
    add_wheel,
    body_section,
    canopy_section,
    export_vehicle,
    loft,
    look_at,
    make_material,
    output_directory,
    parent_keep_transform,
    render_preview,
    reset_scene,
    roof_section,
    set_input,
    subtract_wheel_arches,
)


def materials() -> dict[str, bpy.types.Material]:
    return {
        "Paint": make_material(
            "Paint",
            (0.72, 0.055, 0.035, 1.0),
            metallic=0.56,
            roughness=0.19,
            coat=1.0,
            coat_roughness=0.055,
        ),
        "Glass": make_material(
            "Glass",
            (0.008, 0.026, 0.050, 0.86),
            metallic=0.04,
            roughness=0.065,
            coat=0.72,
            alpha=0.86,
        ),
        "Carbon": make_material(
            "Carbon", (0.009, 0.013, 0.018, 1.0), metallic=0.58, roughness=0.30
        ),
        "DarkMetal": make_material(
            "DarkMetal", (0.020, 0.026, 0.034, 1.0), metallic=0.92, roughness=0.24
        ),
        "Interior": make_material(
            "Interior", (0.018, 0.019, 0.024, 1.0), roughness=0.66
        ),
        "Tire": make_material("Tire", (0.004, 0.005, 0.006, 1.0), roughness=0.90),
        "Rim": make_material(
            "Rim", (0.18, 0.20, 0.22, 1.0), metallic=0.96, roughness=0.18
        ),
        "Brake": make_material(
            "Brake", (0.22, 0.24, 0.26, 1.0), metallic=0.90, roughness=0.30
        ),
        "Accent": make_material(
            "Accent", (1.0, 0.64, 0.05, 1.0), metallic=0.30, roughness=0.18, coat=0.65
        ),
        "TailLight": make_material(
            "TailLight",
            (0.80, 0.004, 0.010, 1.0),
            roughness=0.07,
            coat=0.85,
            emission=(1.0, 0.003, 0.006, 1.0),
            emission_strength=3.4,
        ),
        "HeadLight": make_material(
            "HeadLight",
            (0.62, 0.86, 1.0, 1.0),
            roughness=0.05,
            coat=0.92,
            emission=(0.52, 0.82, 1.0, 1.0),
            emission_strength=4.2,
        ),
        "Plate": make_material(
            "Plate", (0.72, 0.75, 0.73, 1.0), metallic=0.08, roughness=0.34
        ),
    }


def build_vehicle() -> tuple[bpy.types.Object, dict[str, bpy.types.Material]]:
    reset_scene()
    palette = materials()
    root = bpy.data.objects.new("RallyRSV5", None)
    bpy.context.collection.objects.link(root)
    root["assetRole"] = "hero-vehicle"
    root["authoringTool"] = "Blender 4.5 LTS + Scripts/build_rally_rs_v5_blender.py"
    root["license"] = "project-original"
    root["productionRevision"] = 5
    root["vehicleClass"] = "rally-rs"

    body_stations = [
        (-1.64, 0.38, 0.24, 0.42, 0.46),
        (-1.50, 0.66, 0.19, 0.53, 0.57),
        (-1.28, 0.82, 0.14, 0.66, 0.70),
        (-1.00, 0.89, 0.12, 0.73, 0.77),
        (-0.62, 0.88, 0.12, 0.72, 0.76),
        (-0.18, 0.86, 0.12, 0.70, 0.74),
        (0.28, 0.87, 0.12, 0.73, 0.77),
        (0.68, 0.90, 0.13, 0.78, 0.82),
        (1.00, 0.91, 0.14, 0.80, 0.84),
        (1.24, 0.88, 0.16, 0.73, 0.77),
        (1.44, 0.80, 0.20, 0.62, 0.66),
        (1.58, 0.62, 0.25, 0.49, 0.53),
    ]
    body = loft(
        "paint_body_shell", body_stations, body_section, palette["Paint"], root, subdivision=2
    )
    subtract_wheel_arches(body, [(-1.02, 0.36), (0.98, 0.36)])

    canopy_stations = [
        (-0.70, 0.27, 0.69, 0.77, 0.83),
        (-0.54, 0.47, 0.70, 0.88, 1.00),
        (-0.24, 0.58, 0.71, 1.02, 1.17),
        (0.16, 0.60, 0.72, 1.10, 1.26),
        (0.52, 0.59, 0.72, 1.09, 1.25),
        (0.78, 0.54, 0.71, 1.00, 1.15),
        (0.98, 0.43, 0.70, 0.86, 0.97),
        (1.10, 0.25, 0.68, 0.74, 0.79),
    ]
    loft(
        "glass_canopy", canopy_stations, canopy_section, palette["Glass"], root, subdivision=2
    )
    roof_stations = [
        (-0.30, 0.34, 1.155, 1.17, 1.20),
        (0.10, 0.40, 1.235, 1.25, 1.28),
        (0.48, 0.39, 1.225, 1.24, 1.27),
        (0.72, 0.31, 1.125, 1.14, 1.17),
    ]
    loft(
        "paint_roof_panel", roof_stations, roof_section, palette["Paint"], root, subdivision=2
    )

    add_box(
        "interior_cockpit", (1.00, 1.26, 0.10), (0.0, 0.15, 0.72),
        palette["Interior"], root, bevel=0.055
    )
    add_box(
        "interior_dashboard", (0.91, 0.22, 0.16), (0.0, -0.40, 0.83),
        palette["Interior"], root, rotation=(math.radians(-8), 0.0, 0.0), bevel=0.045
    )
    add_bucket_seat("interior_seat_left", -0.26, palette, root)
    add_bucket_seat("interior_seat_right", 0.26, palette, root)

    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(
            f"dark_window_belt_{side_name}", (0.030, 1.42, 0.045),
            (side * 0.60, 0.16, 0.715), palette["DarkMetal"], root, bevel=0.012
        )
        add_box(
            f"dark_side_skirt_{side_name}", (0.075, 2.05, 0.11),
            (side * 0.86, 0.02, 0.18), palette["Carbon"], root, bevel=0.025
        )
        add_box(
            f"carbon_side_vent_{side_name}", (0.055, 0.34, 0.25),
            (side * 0.875, 0.48, 0.43), palette["Carbon"], root,
            rotation=(math.radians(-7), 0.0, 0.0), bevel=0.035
        )
        add_box(
            f"mirror_{side_name}", (0.22, 0.18, 0.095),
            (side * 0.94, -0.39, 0.84), palette["Paint"], root,
            rotation=(0.0, 0.0, math.radians(side * 8)), bevel=0.055
        )
        add_box(
            f"mud_flap_front_{side_name}", (0.035, 0.12, 0.22),
            (side * 0.89, -0.73, 0.21), palette["Carbon"], root, bevel=0.008
        )
        add_box(
            f"mud_flap_rear_{side_name}", (0.035, 0.12, 0.24),
            (side * 0.90, 1.28, 0.22), palette["Carbon"], root, bevel=0.008
        )

    add_box(
        "dark_front_splitter", (1.50, 0.28, 0.065), (0.0, -1.50, 0.16),
        palette["Carbon"], root, rotation=(math.radians(-3), 0.0, 0.0), bevel=0.025
    )
    add_box(
        "front_grille", (0.82, 0.055, 0.22), (0.0, -1.655, 0.34),
        palette["Carbon"], root, bevel=0.040
    )
    add_box(
        "front_skid_plate", (0.68, 0.20, 0.045), (0.0, -1.60, 0.18),
        palette["DarkMetal"], root, rotation=(math.radians(-14), 0.0, 0.0), bevel=0.018
    )
    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(
            f"head_light_{side_name}", (0.36, 0.045, 0.090),
            (side * 0.48, -1.61, 0.53), palette["HeadLight"], root,
            rotation=(0.0, math.radians(side * -7), 0.0), bevel=0.026
        )
        add_box(
            f"front_intake_{side_name}", (0.27, 0.055, 0.16),
            (side * 0.59, -1.61, 0.30), palette["Carbon"], root, bevel=0.035
        )
        add_box(
            f"paint_hood_vent_surround_{side_name}", (0.25, 0.34, 0.028),
            (side * 0.31, -0.93, 0.73), palette["Paint"], root,
            rotation=(math.radians(-9), 0.0, 0.0), bevel=0.020
        )
        add_box(
            f"dark_hood_vent_{side_name}", (0.17, 0.25, 0.018),
            (side * 0.31, -0.92, 0.746), palette["Carbon"], root,
            rotation=(math.radians(-9), 0.0, 0.0), bevel=0.015
        )

    add_box(
        "paint_roof_scoop", (0.30, 0.42, 0.11), (0.0, 0.10, 1.31),
        palette["Paint"], root, rotation=(math.radians(-4), 0.0, 0.0), bevel=0.065
    )
    add_box(
        "roof_scoop_intake", (0.21, 0.08, 0.055), (0.0, -0.105, 1.315),
        palette["Carbon"], root, bevel=0.020
    )

    add_box(
        "paint_rear_fascia", (1.43, 0.10, 0.40), (0.0, 1.55, 0.47),
        palette["Paint"], root, bevel=0.075
    )
    add_box(
        "rear_light_recess", (1.26, 0.050, 0.16), (0.0, 1.607, 0.60),
        palette["DarkMetal"], root, bevel=0.042
    )
    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(
            f"tail_light_{side_name}", (0.45, 0.030, 0.080),
            (side * 0.42, 1.638, 0.61), palette["TailLight"], root,
            rotation=(0.0, math.radians(side * 5), math.radians(side * 7)), bevel=0.024
        )
    add_box(
        "rear_plate_recess", (0.40, 0.055, 0.13), (0.0, 1.615, 0.39),
        palette["Carbon"], root, bevel=0.030
    )
    add_box(
        "rear_plate", (0.28, 0.018, 0.070), (0.0, 1.648, 0.39),
        palette["Plate"], root, bevel=0.012
    )
    add_box(
        "dark_rear_diffuser", (1.22, 0.30, 0.12), (0.0, 1.45, 0.19),
        palette["Carbon"], root, rotation=(math.radians(8), 0.0, 0.0), bevel=0.030
    )
    add_cylinder(
        "exhaust_center", 0.075, 0.18, (0.0, 1.62, 0.28),
        palette["DarkMetal"], root, rotation=(math.pi * 0.5, 0.0, 0.0), bevel=0.010
    )

    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(
            f"paint_wing_upright_{side_name}", (0.060, 0.10, 0.34),
            (side * 0.45, 1.20, 0.93), palette["Paint"], root,
            rotation=(math.radians(-8), 0.0, 0.0), bevel=0.020
        )
    add_box(
        "paint_rally_wing", (1.40, 0.28, 0.055), (0.0, 1.24, 1.10),
        palette["Paint"], root, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.035
    )
    add_box(
        "carbon_wing_lower", (1.30, 0.16, 0.032), (0.0, 1.20, 1.04),
        palette["Carbon"], root, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.020
    )

    for axle, longitudinal, radius in (("front", -1.02, 0.36), ("rear", 0.98, 0.36)):
        for side_name, side in (("left", -1.0), ("right", 1.0)):
            add_wheel(axle, side_name, side, longitudinal, radius, palette, root)
            add_torus(
                f"tire_guard_{axle}_{side_name}", radius - 0.055, 0.018,
                (side * 0.76, longitudinal, radius), palette["Tire"], root
            )

    return root, palette


def render_presentation_source(
    root: bpy.types.Object,
    palette: dict[str, bpy.types.Material],
    output: pathlib.Path,
) -> None:
    paint_shader = palette["Paint"].node_tree.nodes.get("Principled BSDF")
    original_base = paint_shader.inputs["Base Color"].default_value[:]
    original_metallic = paint_shader.inputs["Metallic"].default_value
    original_roughness = paint_shader.inputs["Roughness"].default_value
    set_input(paint_shader, "Base Color", (0.94, 0.94, 0.94, 1.0))
    set_input(paint_shader, "Metallic", 0.08)
    set_input(paint_shader, "Roughness", 0.24)

    shadow_material = make_material(
        "PresentationShadow", (0.004, 0.006, 0.012, 0.34), roughness=1.0, alpha=0.34
    )
    bpy.ops.mesh.primitive_uv_sphere_add(segments=64, ring_count=24, location=(0.0, 0.12, 0.025))
    shadow = bpy.context.object
    shadow.name = "presentation_contact_shadow"
    shadow.scale = (0.94, 1.55, 0.018)
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    shadow.data.materials.append(shadow_material)

    def area(name, location, energy, color, size):
        data = bpy.data.lights.new(name, "AREA")
        data.energy = energy
        data.color = color
        data.shape = "DISK"
        data.size = size
        light = bpy.data.objects.new(name, data)
        bpy.context.collection.objects.link(light)
        light.location = location
        look_at(light, (0.0, 0.05, 0.55))
        return light

    area("presentation_key", (4.0, 1.2, 4.5), 1500, (0.88, 0.94, 1.0), 4.2)
    area("presentation_fill", (-3.2, -1.8, 2.4), 980, (0.48, 0.72, 1.0), 3.4)
    area("presentation_rim", (-2.0, 3.2, 2.7), 920, (1.0, 0.28, 0.12), 3.0)

    camera_data = bpy.data.cameras.new("presentation_camera")
    camera = bpy.data.objects.new("presentation_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (3.7, 4.5, 2.55)
    camera_data.type = "ORTHO"
    camera_data.ortho_scale = 4.8
    look_at(camera, (0.0, 0.05, 0.58))

    scene = bpy.context.scene
    scene.camera = camera
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1024
    scene.render.resolution_y = 1024
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = True
    scene.render.filepath = str(output / "rally_rs_presentation_source.png")
    bpy.ops.render.render(write_still=True)

    set_input(paint_shader, "Base Color", original_base)
    set_input(paint_shader, "Metallic", original_metallic)
    set_input(paint_shader, "Roughness", original_roughness)
    bpy.data.objects.remove(shadow, do_unlink=True)
    for name in (
        "presentation_key", "presentation_fill", "presentation_rim", "presentation_camera"
    ):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def main() -> None:
    output = output_directory()
    root, palette = build_vehicle()
    render_preview(root, output, "rally_rs_v5_preview.png")
    render_presentation_source(root, palette, output)
    export_vehicle(root, output, "rally_rs_v5")
    print(f"wrote {output / 'rally_rs_v5.blend'}")
    print(f"wrote {output / 'rally_rs_v5.usda'}")
    print(f"wrote {output / 'rally_rs_v5_preview.png'}")
    print(f"wrote {output / 'rally_rs_presentation_source.png'}")


if __name__ == "__main__":
    main()
