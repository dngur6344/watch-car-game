#!/usr/bin/env python3
"""Build the project-original Alpine enhanced environment pack in Blender.

Run with Blender 4.5 LTS or newer:
  blender --background --factory-startup --python Scripts/build_alpine_environment_blender.py -- <output-dir>

The editable .blend is the source of truth. A compact deterministic USDA writer
keeps the existing RealityKit hierarchy and material-name contract intact.
"""

from __future__ import annotations

import math
import pathlib
import random
import subprocess
import sys

import bpy
from mathutils import Vector


ROOT_NAME = "AlpineEnvironmentEnhanced"
SOURCE_NAME = "alpine_environment_enhanced.usda"
PACKAGE_NAME = "alpine_environment_enhanced.usdz"
TOOL_NAME = "Blender 4.5 LTS + Scripts/build_alpine_environment_blender.py@1.0.0"


def output_directory() -> pathlib.Path:
    try:
        separator = sys.argv.index("--")
        destination = pathlib.Path(sys.argv[separator + 1]).resolve()
    except (ValueError, IndexError):
        raise SystemExit("usage: blender ... --python build_alpine_environment_blender.py -- <output-directory>")
    destination.mkdir(parents=True, exist_ok=True)
    return destination


def reset_scene() -> None:
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for blocks in (
        bpy.data.meshes,
        bpy.data.materials,
        bpy.data.cameras,
        bpy.data.lights,
    ):
        for block in list(blocks):
            blocks.remove(block)


def set_shader_input(shader, name: str, value) -> None:
    socket = shader.inputs.get(name)
    if socket is not None:
        socket.default_value = value


def make_material(
    name: str,
    color: tuple[float, float, float, float],
    roughness: float,
) -> bpy.types.Material:
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    material.diffuse_color = color
    shader = material.node_tree.nodes.get("Principled BSDF")
    set_shader_input(shader, "Base Color", color)
    set_shader_input(shader, "Roughness", roughness)
    set_shader_input(shader, "Coat Weight", 0.08 if name == "Accent" else 0.0)
    return material


def make_empty(name: str, parent: bpy.types.Object | None = None) -> bpy.types.Object:
    obj = bpy.data.objects.new(name, None)
    bpy.context.collection.objects.link(obj)
    obj.empty_display_type = "PLAIN_AXES"
    obj.empty_display_size = 0.5
    obj.parent = parent
    return obj


def make_mesh(
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
    obj.parent = parent
    obj.data.materials.append(material)
    for polygon in obj.data.polygons:
        polygon.use_smooth = True
    obj["topology"] = "closed-volume"
    return obj


def append_ring_volume(
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    *,
    center: tuple[float, float, float],
    radii: tuple[float, float, float],
    seed: int,
    segments: int = 8,
) -> None:
    randomizer = random.Random(seed)
    start = len(vertices)
    cx, cy, cz = center
    rx, ry, rz = radii
    ring_heights = (-0.42, 0.0, 0.46)
    ring_scales = (0.72, 1.0, 0.68)
    for ring_index, (height, scale) in enumerate(zip(ring_heights, ring_scales)):
        for segment in range(segments):
            angle = math.tau * segment / segments
            variation = 0.88 + randomizer.random() * 0.23
            vertices.append(
                (
                    cx + math.cos(angle) * rx * scale * variation,
                    cy + math.sin(angle) * ry * scale * (1.05 - 0.04 * ring_index),
                    cz + height * rz + math.sin(angle * 2 + seed) * rz * 0.055,
                )
            )
    bottom = len(vertices)
    vertices.append((cx, cy, cz - rz * 0.62))
    top = len(vertices)
    vertices.append((cx - rx * 0.07, cy + ry * 0.04, cz + rz * 0.67))
    for ring in range(2):
        first = start + ring * segments
        following = first + segments
        for segment in range(segments):
            following_segment = (segment + 1) % segments
            faces.append(
                (
                    first + segment,
                    first + following_segment,
                    following + following_segment,
                    following + segment,
                )
            )
    for segment in range(segments):
        following_segment = (segment + 1) % segments
        faces.append((bottom, start + following_segment, start + segment))
        upper = start + segments * 2
        faces.append((upper + segment, upper + following_segment, top))


def boulder_cluster(
    name: str,
    specs: list[tuple[tuple[float, float, float], tuple[float, float, float], int]],
    material: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    for center, radii, seed in specs:
        append_ring_volume(vertices, faces, center=center, radii=radii, seed=seed)
    return make_mesh(name, vertices, faces, material, parent)


def append_frustum(
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    *,
    center: tuple[float, float],
    z_bottom: float,
    z_top: float,
    radius_bottom: float,
    radius_top: float,
    segments: int = 8,
) -> None:
    start = len(vertices)
    cx, cy = center
    for z, radius in ((z_bottom, radius_bottom), (z_top, radius_top)):
        for segment in range(segments):
            angle = math.tau * segment / segments
            vertices.append((cx + math.cos(angle) * radius, cy + math.sin(angle) * radius, z))
    for segment in range(segments):
        following = (segment + 1) % segments
        faces.append((start + segment, start + following, start + segments + following, start + segments + segment))
    faces.append(tuple(start + segment for segment in reversed(range(segments))))
    faces.append(tuple(start + segments + segment for segment in range(segments)))


def pine_meshes(
    name: str,
    trees: list[tuple[float, float, float, float]],
    materials: dict[str, bpy.types.Material],
    parent: bpy.types.Object,
) -> tuple[bpy.types.Object, bpy.types.Object]:
    trunk_vertices: list[tuple[float, float, float]] = []
    trunk_faces: list[tuple[int, ...]] = []
    crown_vertices: list[tuple[float, float, float]] = []
    crown_faces: list[tuple[int, ...]] = []
    for index, (x, y, height, width) in enumerate(trees):
        append_frustum(
            trunk_vertices,
            trunk_faces,
            center=(x, y),
            z_bottom=0,
            z_top=height * 0.70,
            radius_bottom=width * 0.14,
            radius_top=width * 0.07,
            segments=7,
        )
        for tier, (bottom, top, radius) in enumerate(
            ((0.25, 0.64, 1.0), (0.45, 0.80, 0.78), (0.64, 0.98, 0.53))
        ):
            sway = (index % 3 - 1) * width * 0.035 * tier
            append_frustum(
                crown_vertices,
                crown_faces,
                center=(x + sway, y),
                z_bottom=height * bottom,
                z_top=height * top,
                radius_bottom=width * radius,
                radius_top=width * 0.04,
                segments=8,
            )
    return (
        make_mesh(f"{name}_Trunks", trunk_vertices, trunk_faces, materials["Terrain"], parent),
        make_mesh(f"{name}_Needles", crown_vertices, crown_faces, materials["Vegetation"], parent),
    )


def ridge_geometry(
    *,
    width: float,
    depth: float,
    height: float,
    offset_x: float = 0,
    snow: bool = False,
) -> tuple[list[tuple[float, float, float]], list[tuple[int, ...]]]:
    x_count = 7 if snow else 11
    y_count = 5
    top_vertices: list[tuple[float, float, float]] = []
    for y_index in range(y_count):
        y_fraction = y_index / (y_count - 1) - 0.5
        for x_index in range(x_count):
            x_fraction = x_index / (x_count - 1) - 0.5
            peak = max(0.0, 1.0 - abs(x_fraction * 1.62))
            erosion = 0.11 * math.sin(x_index * 2.17 + y_index * 1.31)
            back_scale = 0.82 + 0.17 * math.cos(y_fraction * math.pi)
            z = max(0.08, (peak + erosion) * height * back_scale)
            if snow:
                z += 0.10
            top_vertices.append((offset_x + x_fraction * width, y_fraction * depth, z))
    bottom_vertices = [
        (x, y, max(0.0, z - 0.16) if snow else 0.0)
        for x, y, z in top_vertices
    ]
    vertices = top_vertices + bottom_vertices
    faces: list[tuple[int, ...]] = []
    top_count = len(top_vertices)
    for y_index in range(y_count - 1):
        for x_index in range(x_count - 1):
            first = y_index * x_count + x_index
            faces.append((first, first + 1, first + x_count + 1, first + x_count))
            faces.append(
                (
                    top_count + first,
                    top_count + first + x_count,
                    top_count + first + x_count + 1,
                    top_count + first + 1,
                )
            )
    perimeter = (
        list(range(x_count))
        + [row * x_count + x_count - 1 for row in range(1, y_count)]
        + list(range((y_count - 1) * x_count + x_count - 2, (y_count - 1) * x_count - 1, -1))
        + [row * x_count for row in range(y_count - 2, 0, -1)]
    )
    for index, first in enumerate(perimeter):
        following = perimeter[(index + 1) % len(perimeter)]
        faces.append((first, following, top_count + following, top_count + first))
    return vertices, faces


def append_box(
    vertices: list[tuple[float, float, float]],
    faces: list[tuple[int, ...]],
    center: tuple[float, float, float],
    size: tuple[float, float, float],
) -> None:
    start = len(vertices)
    cx, cy, cz = center
    sx, sy, sz = (component / 2 for component in size)
    vertices.extend(
        [
            (cx - sx, cy - sy, cz - sz),
            (cx + sx, cy - sy, cz - sz),
            (cx + sx, cy + sy, cz - sz),
            (cx - sx, cy + sy, cz - sz),
            (cx - sx, cy - sy, cz + sz),
            (cx + sx, cy - sy, cz + sz),
            (cx + sx, cy + sy, cz + sz),
            (cx - sx, cy + sy, cz + sz),
        ]
    )
    faces.extend(
        [
            (start, start + 3, start + 2, start + 1),
            (start + 4, start + 5, start + 6, start + 7),
            (start, start + 1, start + 5, start + 4),
            (start + 1, start + 2, start + 6, start + 5),
            (start + 2, start + 3, start + 7, start + 6),
            (start + 3, start, start + 4, start + 7),
        ]
    )


def tunnel_portal(
    name: str,
    material: bpy.types.Material,
    parent: bpy.types.Object,
) -> bpy.types.Object:
    vertices: list[tuple[float, float, float]] = []
    faces: list[tuple[int, ...]] = []
    append_box(vertices, faces, (-8.0, 0.0, 3.0), (2.0, 3.2, 6.0))
    append_box(vertices, faces, (8.0, 0.0, 3.0), (2.0, 3.2, 6.0))
    segments = 10
    inner_radius = 7.0
    outer_radius = 8.4
    depth = 3.2
    start = len(vertices)
    for y in (-depth / 2, depth / 2):
        for radius in (inner_radius, outer_radius):
            for segment in range(segments + 1):
                angle = math.pi * segment / segments
                vertices.append((math.cos(angle) * radius, y, 5.6 + math.sin(angle) * radius))
    ring = segments + 1
    for side in range(2):
        base = start + side * ring * 2
        for segment in range(segments):
            faces.append((base + segment, base + segment + 1, base + ring + segment + 1, base + ring + segment))
    for radius_index in range(2):
        front = start + radius_index * ring
        back = start + ring * 2 + radius_index * ring
        for segment in range(segments):
            faces.append((front + segment, back + segment, back + segment + 1, front + segment + 1))
    return make_mesh(name, vertices, faces, material, parent)


def build_environment() -> tuple[bpy.types.Object, dict[str, bpy.types.Object], dict[str, bpy.types.Material]]:
    reset_scene()
    materials = {
        "Terrain": make_material("Terrain", (0.20, 0.22, 0.20, 1), 0.93),
        "Rock": make_material("Rock", (0.34, 0.39, 0.42, 1), 0.84),
        "Vegetation": make_material("Vegetation", (0.055, 0.20, 0.13, 1), 0.96),
        "Accent": make_material("Accent", (0.78, 0.86, 0.88, 1), 0.68),
    }

    root = make_empty(ROOT_NAME)
    root["authoringTool"] = TOOL_NAME
    root["license"] = "project-original"
    root["productionRevision"] = 3
    root["roadApertureWidth"] = 14.0
    root["roadClearanceHalfWidth"] = 6.0
    root["role"] = "racing-environment-pack"
    root["tier"] = "enhanced"
    root["track"] = "alpine"

    foreground = make_empty("ForegroundLOD", root)
    variants = make_empty("Variants", foreground)
    make_empty("MidgroundLOD", root)
    make_empty("FarLOD", root)
    hero_root = make_empty("Hero", root)

    rock = make_empty("Alpine_RockOutcrop", variants)
    boulder_cluster(
        "LayeredGranite",
        [
            ((-1.7, 0.0, 1.0), (1.8, 1.25, 2.0), 11),
            ((0.3, 0.45, 0.8), (1.55, 1.0, 1.55), 17),
            ((1.9, -0.35, 0.6), (1.15, 0.9, 1.25), 23),
        ],
        materials["Rock"],
        rock,
    )
    boulder_cluster(
        "SnowInCrevices",
        [((0.2, 0.0, 1.85), (1.95, 1.15, 0.32), 41)],
        materials["Accent"],
        rock,
    )

    pine = make_empty("Alpine_PineGrove", variants)
    pine_meshes(
        "PineGrove",
        [(-2.4, 0.2, 5.5, 1.35), (-0.8, -0.4, 6.4, 1.55), (1.1, 0.35, 5.8, 1.45), (2.5, -0.2, 4.8, 1.20)],
        materials,
        pine,
    )
    boulder_cluster(
        "PineGroveFooting",
        [((0.0, 0.0, 0.18), (3.6, 1.45, 0.45), 53)],
        materials["Rock"],
        pine,
    )

    forest = make_empty("Alpine_ForestBelt", variants)
    forest_trees = [
        (-5.2, 0.2, 6.4, 1.4), (-3.5, -0.4, 8.0, 1.8), (-1.5, 0.35, 6.8, 1.5),
        (0.4, -0.3, 8.8, 1.9), (2.7, 0.45, 7.2, 1.6), (4.9, -0.2, 6.3, 1.4),
    ]
    pine_meshes("ForestBelt", forest_trees, materials, forest)
    ridge_vertices, ridge_faces = ridge_geometry(width=13.0, depth=3.5, height=2.5)
    make_mesh("ForestGraniteShelf", ridge_vertices, ridge_faces, materials["Rock"], forest)

    snow_ridge = make_empty("Alpine_SnowRidge", variants)
    ridge_vertices, ridge_faces = ridge_geometry(width=15.5, depth=4.6, height=7.0)
    make_mesh("SnowRidgeGranite", ridge_vertices, ridge_faces, materials["Rock"], snow_ridge)
    cap_vertices, cap_faces = ridge_geometry(width=9.2, depth=4.3, height=7.15, snow=True)
    make_mesh("SnowRidgeCap", cap_vertices, cap_faces, materials["Accent"], snow_ridge)

    hero = make_empty("Alpine_TunnelPeak_Hero", hero_root)
    left_vertices, left_faces = ridge_geometry(width=17.0, depth=10.0, height=17.5, offset_x=-11.8)
    right_vertices, right_faces = ridge_geometry(width=17.0, depth=10.0, height=15.5, offset_x=11.8)
    make_mesh("TunnelPeakLeft", left_vertices, left_faces, materials["Rock"], hero)
    make_mesh("TunnelPeakRight", right_vertices, right_faces, materials["Rock"], hero)
    left_cap, left_cap_faces = ridge_geometry(width=10.0, depth=9.5, height=17.7, offset_x=-11.8, snow=True)
    right_cap, right_cap_faces = ridge_geometry(width=10.0, depth=9.5, height=15.7, offset_x=11.8, snow=True)
    make_mesh("TunnelPeakSnowLeft", left_cap, left_cap_faces, materials["Accent"], hero)
    make_mesh("TunnelPeakSnowRight", right_cap, right_cap_faces, materials["Accent"], hero)
    tunnel_portal("TunnelPortalStone", materials["Terrain"], hero)
    boulder_cluster(
        "TunnelApproachRock",
        [
            ((-9.5, -0.8, 1.1), (2.4, 1.4, 2.2), 71),
            ((9.7, 0.6, 0.9), (2.2, 1.5, 1.8), 79),
        ],
        materials["Rock"],
        hero,
    )

    return root, {
        "ForegroundLOD": foreground,
        "MidgroundLOD": next(child for child in root.children if child.name == "MidgroundLOD"),
        "FarLOD": next(child for child in root.children if child.name == "FarLOD"),
        "Hero": hero_root,
    }, materials


def usd_number(value: float) -> str:
    if abs(value) < 0.000005:
        value = 0.0
    return f"{value:.5f}"


def material_usd(name: str, material: bpy.types.Material) -> str:
    color = material.diffuse_color
    roughness = material.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value
    return f'''        def Material "{name}"
        {{
            token outputs:surface.connect = </{ROOT_NAME}/Materials/{name}/Surface.outputs:surface>
            def Shader "Surface"
            {{
                uniform token info:id = "UsdPreviewSurface"
                color3f inputs:diffuseColor = ({usd_number(color[0])}, {usd_number(color[1])}, {usd_number(color[2])})
                float inputs:metallic = 0.00000
                float inputs:roughness = {usd_number(roughness)}
                token outputs:surface
            }}
        }}'''


def mesh_usd(obj: bpy.types.Object, indent: str = "                ") -> str:
    vertices = [f"({usd_number(vertex.co.x)}, {usd_number(vertex.co.z)}, {usd_number(-vertex.co.y)})" for vertex in obj.data.vertices]
    counts = [str(len(polygon.vertices)) for polygon in obj.data.polygons]
    indices = [str(index) for polygon in obj.data.polygons for index in polygon.vertices]
    material_name = obj.data.materials[0].name
    return f'''{indent}def Mesh "{obj.name}" (
{indent}    prepend apiSchemas = ["MaterialBindingAPI"]
{indent}    customData = {{
{indent}        string topology = "closed-volume"
{indent}    }}
{indent})
{indent}{{
{indent}    uniform bool doubleSided = 1
{indent}    int[] faceVertexCounts = [{", ".join(counts)}]
{indent}    int[] faceVertexIndices = [{", ".join(indices)}]
{indent}    rel material:binding = </{ROOT_NAME}/Materials/{material_name}>
{indent}    point3f[] points = [{", ".join(vertices)}]
{indent}    uniform token subdivisionScheme = "none"
{indent}}}'''


def variant_usd(variant: bpy.types.Object) -> str:
    meshes = sorted((child for child in variant.children if child.type == "MESH"), key=lambda item: item.name)
    mesh_text = "\n".join(mesh_usd(mesh) for mesh in meshes)
    return f'''            def Xform "{variant.name}"
            (
                customData = {{
                    string assetRole = "foreground-variant"
                    double roadClearanceHalfWidth = 6.00000
                }}
            )
            {{
{mesh_text}
            }}'''


def write_usda(
    output: pathlib.Path,
    layers: dict[str, bpy.types.Object],
    materials: dict[str, bpy.types.Material],
) -> pathlib.Path:
    variants_root = next(child for child in layers["ForegroundLOD"].children if child.name == "Variants")
    variants = sorted(variants_root.children, key=lambda item: item.name)
    variant_text = "\n".join(variant_usd(variant) for variant in variants)
    hero = next(child for child in layers["Hero"].children if child.name == "Alpine_TunnelPeak_Hero")
    hero_meshes = "\n".join(
        mesh_usd(mesh, indent="            ")
        for mesh in sorted((child for child in hero.children if child.type == "MESH"), key=lambda item: item.name)
    )
    material_text = "\n".join(material_usd(name, materials[name]) for name in ("Terrain", "Rock", "Vegetation", "Accent"))
    document = f'''#usda 1.0
(
    defaultPrim = "{ROOT_NAME}"
    metersPerUnit = 1
    upAxis = "Y"
)

def Xform "{ROOT_NAME}"
(
    customData = {{
        string authoringTool = "{TOOL_NAME}"
        string license = "project-original"
        int productionRevision = 3
        int revision = 3
        double roadApertureWidth = 14.00000
        double roadClearanceHalfWidth = 6.00000
        string role = "racing-environment-pack"
        string tier = "enhanced"
        string track = "alpine"
    }}
)
{{
    def Scope "Materials"
    {{
{material_text}
    }}

    def Xform "ForegroundLOD"
    (
        customData = {{
            string distanceLayer = "foreground"
            string role = "lod-root"
        }}
    )
    {{
        def Xform "Variants"
        (
            customData = {{
                string role = "variant-root"
            }}
        )
        {{
{variant_text}
        }}
    }}

    def Xform "MidgroundLOD"
    (
        customData = {{
            string distanceLayer = "midground"
            string role = "lod-root"
        }}
    )
    {{
    }}

    def Xform "FarLOD"
    (
        customData = {{
            string distanceLayer = "far"
            string role = "lod-root"
        }}
    )
    {{
    }}

    def Xform "Hero"
    (
        customData = {{
            string role = "hero-root"
        }}
    )
    {{
        def Xform "Alpine_TunnelPeak_Hero"
        (
            customData = {{
                string assetRole = "far-hero"
                double roadApertureWidth = 14.00000
            }}
        )
        {{
{hero_meshes}
        }}
    }}
}}
'''
    destination = output / SOURCE_NAME
    destination.write_text(document, encoding="utf-8")
    return destination


def stage_and_render(
    output: pathlib.Path,
    root: bpy.types.Object,
    layers: dict[str, bpy.types.Object],
) -> None:
    variants = next(child for child in layers["ForegroundLOD"].children if child.name == "Variants")
    positions = {
        "Alpine_RockOutcrop": (-8.2, 3.0, 0.0),
        "Alpine_PineGrove": (-2.8, 2.0, 0.0),
        "Alpine_ForestBelt": (4.2, 5.0, 0.0),
        "Alpine_SnowRidge": (11.5, 9.0, 0.0),
    }
    for variant in variants.children:
        variant.location = positions[variant.name]
    layers["Hero"].location = (0.0, 20.0, -1.0)

    bpy.ops.mesh.primitive_plane_add(size=90, location=(0, 11, -0.08))
    ground = bpy.context.object
    ground.name = "PreviewGround"
    ground.data.materials.append(bpy.data.materials["Terrain"])

    bpy.ops.object.camera_add(location=(25, -34, 21))
    camera = bpy.context.object
    target = Vector((2.0, 10.0, 5.5))
    camera.rotation_euler = (target - camera.location).to_track_quat("-Z", "Y").to_euler()
    camera.data.lens = 54
    bpy.context.scene.camera = camera

    bpy.ops.object.light_add(type="AREA", location=(-12, -10, 28))
    key = bpy.context.object
    key.data.energy = 1900
    key.data.shape = "DISK"
    key.data.size = 12
    key.rotation_euler = ((Vector((0, 8, 5)) - key.location).to_track_quat("-Z", "Y").to_euler())
    bpy.ops.object.light_add(type="AREA", location=(22, 3, 14))
    fill = bpy.context.object
    fill.data.energy = 900
    fill.data.size = 10
    fill.rotation_euler = ((Vector((2, 10, 4)) - fill.location).to_track_quat("-Z", "Y").to_euler())
    bpy.ops.object.light_add(type="AREA", location=(-2, 30, 20))
    rim = bpy.context.object
    rim.data.energy = 1300
    rim.data.size = 9
    rim.rotation_euler = ((Vector((0, 15, 6)) - rim.location).to_track_quat("-Z", "Y").to_euler())

    scene = bpy.context.scene
    scene.render.engine = "BLENDER_EEVEE_NEXT"
    scene.render.resolution_x = 1280
    scene.render.resolution_y = 720
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.filepath = str(output / "alpine_environment_blender_preview.png")
    scene.render.film_transparent = False
    scene.world.color = (0.05, 0.08, 0.12)
    bpy.ops.wm.save_as_mainfile(filepath=str(output / "alpine_environment_enhanced.blend"))
    bpy.ops.render.render(write_still=True)


def package_usdz(output: pathlib.Path) -> pathlib.Path:
    destination = output / PACKAGE_NAME
    if destination.exists():
        destination.unlink()
    subprocess.run(
        ["/usr/bin/usdzip", "--checkCompliance", PACKAGE_NAME, SOURCE_NAME],
        cwd=output,
        check=True,
    )
    return destination


def main() -> None:
    output = output_directory()
    root, layers, materials = build_environment()
    write_usda(output, layers, materials)
    package_usdz(output)
    stage_and_render(output, root, layers)
    print(f"Built project-original Alpine enhanced environment in {output}")


if __name__ == "__main__":
    main()
