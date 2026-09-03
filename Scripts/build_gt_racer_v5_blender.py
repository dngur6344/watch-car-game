#!/usr/bin/env python3
"""Build the project-original revision 5 GT hero car with Blender.

Run with Blender 4.5 LTS or newer:
  blender --background --factory-startup --python Scripts/build_gt_racer_v5_blender.py -- <output-dir>

The script writes an editable .blend source, a Y-up USDA runtime source, and a
studio preview. USDZ packaging remains a separate deterministic repository step.
"""

from __future__ import annotations

import math
import pathlib
import sys

import bpy
from mathutils import Vector


def output_directory() -> pathlib.Path:
    try:
        separator = sys.argv.index("--")
        destination = pathlib.Path(sys.argv[separator + 1]).resolve()
    except (ValueError, IndexError):
        raise SystemExit("usage: blender ... --python build_gt_racer_v5_blender.py -- <output-directory>")
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for block in (bpy.data.meshes, bpy.data.curves, bpy.data.materials, bpy.data.cameras, bpy.data.lights):
        for item in list(block):
            block.remove(item)


def set_input(shader, name: str, value) -> None:
    socket = shader.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    *,
    metallic: float = 0.0,
    roughness: float = 0.4,
    coat: float = 0.0,
    coat_roughness: float = 0.08,
    alpha: float = 1.0,
    emission: tuple[float, float, float, float] | None = None,
    emission_strength: float = 0.0,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = color
    shader = material.node_tree.nodes.get("Principled BSDF")
    set_input(shader, "Base Color", color)
    set_input(shader, "Metallic", metallic)
    set_input(shader, "Roughness", roughness)
    set_input(shader, "Coat Weight", coat)
    set_input(shader, "Coat Roughness", coat_roughness)
    set_input(shader, "Alpha", alpha)
    if emission is not None:
        set_input(shader, "Emission Color", emission)
        set_input(shader, "Emission Strength", emission_strength)
    if alpha < 1.0:
        material.surface_render_method = "DITHERED"
    return material


def assign_material(obj: bpy.types.Object, material: bpy.types.Material) -> None:
    if obj.data and hasattr(obj.data, "materials"):
        obj.data.materials.append(material)


def smooth(obj: bpy.types.Object) -> None:
    if obj.type != "MESH":
        return
    for polygon in obj.data.polygons:
        polygon.use_smooth = True


def apply_modifier(obj: bpy.types.Object, modifier: bpy.types.Modifier) -> None:
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.modifier_apply(modifier=modifier.name)
    obj.select_set(False)


def add_bevel(obj: bpy.types.Object, width: float, segments: int = 3) -> None:
    modifier = obj.modifiers.new("Production bevel", "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    apply_modifier(obj, modifier)
    smooth(obj)


def parent_keep_transform(obj: bpy.types.Object, parent: bpy.types.Object) -> None:
    world = obj.matrix_world.copy()
    obj.parent = parent
    obj.matrix_world = world


def mesh_object(
    name: str,
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    material: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(f"{name}_mesh")
    mesh.from_pydata(vertices, [], faces)
    mesh.update(calc_edges=True)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    assign_material(obj, material)
    parent_keep_transform(obj, parent)
    smooth(obj)
    return obj


def loft(
    name: str,
    stations: list[tuple[float, float, float, float, float]],
    section,
    material: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    subdivision: int = 2,
) -> bpy.types.Object:
    rings = [section(width, bottom, shoulder, top, longitudinal) for longitudinal, width, bottom, shoulder, top in stations]
    ring_size = len(rings[0])
    vertices = [(x, longitudinal, height) for longitudinal, ring in zip((item[0] for item in stations), rings) for x, height in ring]
    faces: list[tuple[int, ...]] = []
    for station_index in range(len(rings) - 1):
        start = station_index * ring_size
        following = (station_index + 1) * ring_size
        for point in range(ring_size):
            next_point = (point + 1) % ring_size
            faces.append((start + point, start + next_point, following + next_point, following + point))
    faces.append(tuple(reversed(range(ring_size))))
    final_start = (len(rings) - 1) * ring_size
    faces.append(tuple(final_start + point for point in range(ring_size)))
    obj = mesh_object(name, vertices, faces, material, parent)
    if subdivision:
        modifier = obj.modifiers.new("Automotive surface", "SUBSURF")
        modifier.subdivision_type = "CATMULL_CLARK"
        modifier.levels = subdivision
        modifier.render_levels = subdivision
        apply_modifier(obj, modifier)
    return obj


def body_section(width: float, bottom: float, shoulder: float, top: float, _longitudinal: float):
    left = [
        (-width * 0.52, bottom),
        (-width * 0.82, bottom + 0.018),
        (-width * 0.97, bottom + 0.070),
        (-width, bottom + 0.160),
        (-width, shoulder - 0.155),
        (-width * 0.97, shoulder - 0.055),
        (-width * 0.88, shoulder + 0.015),
        (-width * 0.72, top - 0.030),
        (-width * 0.46, top + 0.015),
        (0.0, top + 0.035),
    ]
    return left + [(-x, height) for x, height in reversed(left[:-1])]


def canopy_section(width: float, bottom: float, shoulder: float, top: float, _longitudinal: float):
    left = [
        (-width * 0.92, bottom),
        (-width, bottom + 0.075),
        (-width * 0.93, shoulder),
        (-width * 0.76, top - 0.075),
        (-width * 0.46, top + 0.005),
        (0.0, top + 0.035),
    ]
    return left + [(-x, height) for x, height in reversed(left[:-1])]


def roof_section(width: float, bottom: float, _shoulder: float, top: float, _longitudinal: float):
    points = []
    center = (bottom + top) * 0.5
    vertical = (top - bottom) * 0.5
    for index in range(16):
        angle = math.tau * index / 16
        points.append((math.cos(angle) * width, center + math.sin(angle) * vertical))
    return points


def add_box(
    name: str,
    dimensions: tuple[float, float, float],
    location: tuple[float, float, float],
    material: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    bevel: float = 0.025,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cube_add(location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = dimensions
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    assign_material(obj, material)
    if bevel:
        add_bevel(obj, bevel)
    parent_keep_transform(obj, parent)
    return obj


def add_cylinder(
    name: str,
    radius: float,
    depth: float,
    location: tuple[float, float, float],
    material: bpy.types.Material,
    parent: bpy.types.Object,
    *,
    rotation: tuple[float, float, float] = (0.0, 0.0, 0.0),
    vertices: int = 48,
    bevel: float = 0.012,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=location, rotation=rotation)
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    if bevel:
        add_bevel(obj, bevel, 2)
    parent_keep_transform(obj, parent)
    return obj


def add_torus(
    name: str,
    major_radius: float,
    minor_radius: float,
    location: tuple[float, float, float],
    material: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    bpy.ops.mesh.primitive_torus_add(
        major_segments=48,
        minor_segments=16,
        location=location,
        rotation=(0.0, math.pi * 0.5, 0.0),
        major_radius=major_radius,
        minor_radius=minor_radius,
    )
    obj = bpy.context.object
    obj.name = name
    assign_material(obj, material)
    smooth(obj)
    parent_keep_transform(obj, parent)
    return obj


def subtract_wheel_arches(body: bpy.types.Object, wheel_positions: list[tuple[float, float]]) -> None:
    for axle, (longitudinal, radius) in enumerate(wheel_positions):
        for side in (-1.0, 1.0):
            bpy.ops.mesh.primitive_cylinder_add(
                vertices=64,
                radius=radius + 0.055,
                depth=0.48,
                location=(side * 0.79, longitudinal, radius),
                rotation=(0.0, math.pi * 0.5, 0.0),
            )
            cutter = bpy.context.object
            cutter.name = f"wheel_arch_cutter_{axle}_{'left' if side < 0 else 'right'}"
            modifier = body.modifiers.new(cutter.name, "BOOLEAN")
            modifier.operation = "DIFFERENCE"
            modifier.solver = "EXACT"
            modifier.object = cutter
            apply_modifier(body, modifier)
            bpy.data.objects.remove(cutter, do_unlink=True)
    add_bevel(body, 0.018, 2)


def add_wheel(
    axle: str,
    side_name: str,
    side: float,
    longitudinal: float,
    radius: float,
    materials: dict[str, bpy.types.Material],
    root: bpy.types.Object,
) -> None:
    center = (side * 0.76, longitudinal, radius)
    wheel_root = bpy.data.objects.new(f"wheel_{axle}_{side_name}", None)
    bpy.context.collection.objects.link(wheel_root)
    wheel_root.location = center
    parent_keep_transform(wheel_root, root)

    add_torus("tire", radius - 0.095, 0.095, center, materials["Tire"], wheel_root)
    outward = (center[0] + side * 0.105, center[1], center[2])
    add_torus("rim_outer", radius * 0.50, 0.026, outward, materials["Rim"], wheel_root)
    add_cylinder(
        "brake_disc",
        radius * 0.48,
        0.024,
        (center[0] + side * 0.078, center[1], center[2]),
        materials["Brake"],
        wheel_root,
        rotation=(0.0, math.pi * 0.5, 0.0),
        bevel=0.006,
    )
    add_cylinder(
        "hub",
        radius * 0.105,
        0.050,
        (center[0] + side * 0.112, center[1], center[2]),
        materials["DarkMetal"],
        wheel_root,
        rotation=(0.0, math.pi * 0.5, 0.0),
        bevel=0.008,
    )
    for index in range(5):
        add_box(
            f"spoke_{index}",
            (0.018, 0.035, radius * 0.70),
            (center[0] + side * 0.126, center[1], center[2]),
            materials["Rim"],
            wheel_root,
            rotation=(math.radians(index * 36), 0.0, 0.0),
            bevel=0.008,
        )
    add_box(
        "caliper",
        (0.030, radius * 0.18, radius * 0.35),
        (center[0] + side * 0.100, center[1] - radius * 0.24, center[2]),
        materials["Accent"],
        wheel_root,
        bevel=0.018,
    )


def add_bucket_seat(name: str, x: float, materials, root) -> None:
    add_box(f"{name}_base", (0.30, 0.38, 0.085), (x, 0.12, 0.64), materials["Interior"], root, bevel=0.045)
    add_box(
        f"{name}_back",
        (0.31, 0.11, 0.31),
        (x, 0.34, 0.77),
        materials["Interior"],
        root,
        rotation=(math.radians(-12), 0.0, 0.0),
        bevel=0.055,
    )
    add_box(f"{name}_headrest", (0.20, 0.10, 0.11), (x, 0.40, 0.94), materials["Interior"], root, bevel=0.040)


def build_gt_vehicle() -> tuple[bpy.types.Object, dict[str, bpy.types.Material]]:
    reset_scene()
    materials = {
        "Paint": make_material("Paint", (0.055, 0.30, 0.66, 1.0), metallic=0.70, roughness=0.16, coat=1.0, coat_roughness=0.045),
        "Glass": make_material("Glass", (0.008, 0.025, 0.060, 0.84), metallic=0.05, roughness=0.055, coat=0.65, alpha=0.84),
        "Carbon": make_material("Carbon", (0.010, 0.014, 0.020, 1.0), metallic=0.55, roughness=0.28, coat=0.22),
        "DarkMetal": make_material("DarkMetal", (0.018, 0.024, 0.034, 1.0), metallic=0.92, roughness=0.22),
        "Interior": make_material("Interior", (0.018, 0.020, 0.026, 1.0), metallic=0.05, roughness=0.62),
        "Tire": make_material("Tire", (0.004, 0.005, 0.006, 1.0), roughness=0.88),
        "Rim": make_material("Rim", (0.28, 0.31, 0.35, 1.0), metallic=0.96, roughness=0.15),
        "Brake": make_material("Brake", (0.23, 0.25, 0.27, 1.0), metallic=0.90, roughness=0.27),
        "Accent": make_material("Accent", (0.04, 0.78, 0.96, 1.0), metallic=0.40, roughness=0.16, coat=0.70),
        "TailLight": make_material("TailLight", (0.72, 0.004, 0.012, 1.0), roughness=0.08, coat=0.82, emission=(1.0, 0.006, 0.012, 1.0), emission_strength=3.2),
        "HeadLight": make_material("HeadLight", (0.55, 0.82, 1.0, 1.0), roughness=0.055, coat=0.90, emission=(0.45, 0.78, 1.0, 1.0), emission_strength=4.0),
        "Plate": make_material("Plate", (0.72, 0.75, 0.72, 1.0), metallic=0.10, roughness=0.30),
    }

    root = bpy.data.objects.new("GTRacerV5", None)
    bpy.context.collection.objects.link(root)
    root["assetRole"] = "hero-vehicle"
    root["authoringTool"] = "Blender 4.5 LTS + Scripts/build_gt_racer_v5_blender.py"
    root["license"] = "project-original"
    root["productionRevision"] = 5

    body_stations = [
        (-1.78, 0.34, 0.21, 0.37, 0.40),
        (-1.62, 0.60, 0.17, 0.47, 0.51),
        (-1.38, 0.74, 0.14, 0.57, 0.61),
        (-1.10, 0.82, 0.12, 0.65, 0.69),
        (-0.78, 0.84, 0.11, 0.67, 0.72),
        (-0.34, 0.83, 0.11, 0.64, 0.69),
        (0.12, 0.84, 0.11, 0.63, 0.68),
        (0.52, 0.86, 0.11, 0.66, 0.71),
        (0.86, 0.87, 0.12, 0.69, 0.73),
        (1.10, 0.84, 0.13, 0.66, 0.70),
        (1.36, 0.78, 0.16, 0.59, 0.63),
        (1.58, 0.70, 0.19, 0.51, 0.55),
        (1.72, 0.62, 0.22, 0.45, 0.49),
    ]
    body = loft("paint_body_shell", body_stations, body_section, materials["Paint"], root, subdivision=2)
    subtract_wheel_arches(body, [(-1.08, 0.34), (1.04, 0.35)])

    canopy_stations = [
        (-0.82, 0.24, 0.62, 0.68, 0.73),
        (-0.68, 0.39, 0.63, 0.76, 0.85),
        (-0.44, 0.51, 0.64, 0.86, 0.98),
        (-0.10, 0.56, 0.65, 0.92, 1.05),
        (0.28, 0.56, 0.65, 0.93, 1.06),
        (0.58, 0.51, 0.64, 0.86, 0.99),
        (0.82, 0.40, 0.62, 0.75, 0.86),
        (0.98, 0.22, 0.60, 0.65, 0.70),
    ]
    loft("glass_canopy", canopy_stations, canopy_section, materials["Glass"], root, subdivision=2)
    roof_stations = [
        (-0.42, 0.29, 0.980, 0.995, 1.020),
        (-0.04, 0.35, 1.030, 1.045, 1.070),
        (0.34, 0.34, 1.035, 1.050, 1.075),
        (0.62, 0.27, 0.965, 0.980, 1.005),
    ]
    loft("paint_roof_panel", roof_stations, roof_section, materials["Paint"], root, subdivision=2)

    add_box("interior_cockpit", (0.96, 1.18, 0.10), (0.0, 0.12, 0.67), materials["Interior"], root, bevel=0.055)
    add_box("interior_dashboard", (0.88, 0.22, 0.15), (0.0, -0.43, 0.76), materials["Interior"], root, rotation=(math.radians(-9), 0.0, 0.0), bevel=0.045)
    add_bucket_seat("interior_seat_left", -0.25, materials, root)
    add_bucket_seat("interior_seat_right", 0.25, materials, root)

    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(
            f"dark_window_belt_{side_name}",
            (0.030, 1.30, 0.040),
            (side * 0.575, 0.08, 0.675),
            materials["DarkMetal"],
            root,
            bevel=0.012,
        )
        add_box(f"dark_side_skirt_{side_name}", (0.065, 2.12, 0.095), (side * 0.82, 0.02, 0.18), materials["Carbon"], root, bevel=0.025)
        add_box(f"carbon_side_intake_{side_name}", (0.055, 0.42, 0.22), (side * 0.835, 0.42, 0.40), materials["Carbon"], root, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.035)
        add_box(f"mirror_{side_name}", (0.20, 0.20, 0.085), (side * 0.91, -0.40, 0.77), materials["Paint"], root, rotation=(0.0, 0.0, math.radians(side * 8)), bevel=0.055)

    add_box("dark_front_splitter", (1.42, 0.28, 0.055), (0.0, -1.64, 0.145), materials["Carbon"], root, rotation=(math.radians(-3), 0.0, 0.0), bevel=0.025)
    add_box("front_grille", (0.72, 0.055, 0.18), (0.0, -1.765, 0.30), materials["Carbon"], root, bevel=0.035)
    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(f"head_light_{side_name}", (0.40, 0.045, 0.075), (side * 0.43, -1.735, 0.48), materials["HeadLight"], root, rotation=(0.0, math.radians(side * -8), 0.0), bevel=0.025)
        add_box(f"front_intake_{side_name}", (0.28, 0.055, 0.14), (side * 0.54, -1.74, 0.25), materials["Carbon"], root, bevel=0.035)

    add_box("paint_rear_fascia", (1.34, 0.095, 0.36), (0.0, 1.70, 0.42), materials["Paint"], root, bevel=0.075)
    add_box("rear_light_recess", (1.20, 0.050, 0.13), (0.0, 1.755, 0.53), materials["DarkMetal"], root, bevel=0.040)
    add_box("tail_light_center_bar", (0.92, 0.030, 0.042), (0.0, 1.790, 0.55), materials["TailLight"], root, bevel=0.018)
    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_box(f"tail_light_{side_name}_blade", (0.28, 0.035, 0.065), (side * 0.51, 1.792, 0.55), materials["TailLight"], root, rotation=(0.0, math.radians(side * 8), math.radians(side * 9)), bevel=0.022)
    add_box("rear_plate_recess", (0.38, 0.055, 0.12), (0.0, 1.772, 0.35), materials["Carbon"], root, bevel=0.030)
    add_box("rear_plate", (0.27, 0.018, 0.065), (0.0, 1.805, 0.35), materials["Plate"], root, bevel=0.012)
    add_box("dark_rear_diffuser", (1.18, 0.32, 0.11), (0.0, 1.62, 0.18), materials["Carbon"], root, rotation=(math.radians(7), 0.0, 0.0), bevel=0.030)
    for index, x in enumerate((-0.42, -0.14, 0.14, 0.42)):
        add_box(f"diffuser_fin_{index}", (0.035, 0.32, 0.17), (x, 1.65, 0.16), materials["Carbon"], root, rotation=(math.radians(7), 0.0, 0.0), bevel=0.009)
    for side, side_name in ((-1.0, "left"), (1.0, "right")):
        add_cylinder(f"exhaust_{side_name}", 0.062, 0.16, (side * 0.31, 1.77, 0.24), materials["DarkMetal"], root, rotation=(math.pi * 0.5, 0.0, 0.0), bevel=0.009)

    add_box("paint_ducktail", (1.14, 0.16, 0.038), (0.0, 1.43, 0.635), materials["Paint"], root, rotation=(math.radians(-7), 0.0, 0.0), bevel=0.025)

    for axle, longitudinal, radius in (("front", -1.08, 0.34), ("rear", 1.04, 0.35)):
        add_wheel(axle, "left", -1.0, longitudinal, radius, materials, root)
        add_wheel(axle, "right", 1.0, longitudinal, radius, materials, root)

    return root, materials


def look_at(obj: bpy.types.Object, target: tuple[float, float, float]) -> None:
    direction = Vector(target) - obj.location
    obj.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()


def render_preview(
    root: bpy.types.Object,
    output: pathlib.Path,
    filename: str = "gt_racer_v5_preview.png",
) -> None:
    bpy.ops.mesh.primitive_plane_add(size=18, location=(0.0, 0.0, 0.015))
    floor = bpy.context.object
    floor.name = "preview_floor"
    floor_material = make_material("PreviewFloor", (0.025, 0.032, 0.045, 1.0), metallic=0.12, roughness=0.30)
    assign_material(floor, floor_material)

    world = bpy.context.scene.world
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.012, 0.018, 0.035, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.28

    def area(name, location, energy, color, size):
        light_data = bpy.data.lights.new(name, "AREA")
        light_data.energy = energy
        light_data.color = color
        light_data.shape = "DISK"
        light_data.size = size
        light = bpy.data.objects.new(name, light_data)
        bpy.context.collection.objects.link(light)
        light.location = location
        look_at(light, (0.0, 0.1, 0.55))
        return light

    area("preview_key", (4.0, 2.0, 4.2), 1500, (0.72, 0.86, 1.0), 4.0)
    area("preview_rim", (-3.4, 2.8, 2.2), 1050, (1.0, 0.18, 0.46), 3.2)
    area("preview_fill", (0.0, -4.0, 2.5), 800, (0.20, 0.65, 1.0), 3.0)

    camera_data = bpy.data.cameras.new("preview_camera")
    camera = bpy.data.objects.new("preview_camera", camera_data)
    bpy.context.collection.objects.link(camera)
    camera.location = (4.1, 5.1, 2.55)
    camera_data.lens = 58
    look_at(camera, (0.0, 0.12, 0.55))
    bpy.context.scene.camera = camera

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1400
    scene.render.resolution_y = 900
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output / filename)
    scene.render.film_transparent = False
    bpy.ops.render.render(write_still=True)

    bpy.data.objects.remove(floor, do_unlink=True)
    for name in ("preview_key", "preview_rim", "preview_fill", "preview_camera"):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            bpy.data.objects.remove(obj, do_unlink=True)


def export_vehicle(
    root: bpy.types.Object,
    output: pathlib.Path,
    basename: str = "gt_racer_v5",
) -> None:
    # RealityKit's racing scene advances toward -Z; Blender's authored nose is -Y.
    # The orientation conversion maps -Y to +Z, so turn the complete vehicle around.
    root.rotation_euler.z = math.pi
    root["gameForwardAxis"] = "-Z"
    bpy.ops.wm.save_as_mainfile(filepath=str(output / f"{basename}.blend"))
    bpy.ops.object.select_all(action="DESELECT")
    root.select_set(True)
    for child in root.children_recursive:
        child.select_set(True)
    bpy.context.view_layer.objects.active = root
    bpy.ops.wm.usd_export(
        filepath=str(output / f"{basename}.usda"),
        selected_objects_only=True,
        visible_objects_only=False,
        export_animation=False,
        export_materials=True,
        export_meshes=True,
        export_uvmaps=True,
        export_normals=True,
        export_custom_properties=True,
        export_cameras=False,
        export_lights=False,
        export_subdivision="BEST_MATCH",
        export_textures=False,
        relative_paths=True,
        triangulate_meshes=True,
        convert_orientation=True,
        export_global_forward_selection="NEGATIVE_Z",
        export_global_up_selection="Y",
        meters_per_unit=1.0,
    )
    source_path = output / f"{basename}.usda"
    source_path.write_bytes(source_path.read_bytes().rstrip() + b"\n")


def main() -> None:
    output = output_directory()
    vehicle_root, _ = build_gt_vehicle()
    render_preview(vehicle_root, output)
    export_vehicle(vehicle_root, output)
    print(f"wrote {output / 'gt_racer_v5.blend'}")
    print(f"wrote {output / 'gt_racer_v5.usda'}")
    print(f"wrote {output / 'gt_racer_v5_preview.png'}")


if __name__ == "__main__":
    main()
