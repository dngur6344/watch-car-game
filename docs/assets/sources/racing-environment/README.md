# Racing environment terrain source masters

These three PNG files are immutable project-bound source masters for the Ocean Drive, Alpine Pass, and Desert Circuit terrain PBR atlases. Codex's built-in `image_gen` tool created them on 2026-08-30. They are authoring inputs only: they and the editable USDA files remain outside the app target, and the application performs no runtime asset generation or network fetch.

No stock image, external asset pack, third-party source image, trademark, logo, or recognizable production product was supplied. The sources are project-original and may be used by the Watch Car Racer project owner subject to the applicable OpenAI service terms; no separate third-party attribution is required.

## Selected sources and exact prompts

### Ocean Drive

- File: `ocean_terrain_source.png`
- Built-in source ID: `exec-24ec8976-8a43-4415-8dde-ae56d793ed02`
- SHA-256: `fc62fba112a901ae41adfa497bbce2d889f1a32b432487074bfe650f65d42416`
- Dimensions: 1254×1254, 8-bit RGB PNG
- Prompt:

> Use case: stylized-concept. Asset type: source master for a production iOS racing-game terrain PBR atlas. Create a square, edge-to-edge, orthographic top-down material featuring pale weathered limestone, compacted warm sand, small gravel, sparse salt grass, and dark damp patches. Make it seamless-looking, with even macro variation and no central focal object. Use diffuse neutral studio light with minimal directional shadow and a production-polished stylized-realism treatment in an authored low-poly language. No road markings, cars, buildings, horizon, sky, text, logo, watermark, dramatic baked shadows, perspective, obvious repeating stamps, or isolated props.

### Alpine Pass

- File: `alpine_terrain_source.png`
- Built-in source ID: `exec-508cc22c-ff7b-4908-96e1-06b94ea3661a`
- SHA-256: `735c36b4ab5f958fcb7afc691c9303ceb8086bf138bfde9ed34d58b4d628fba7`
- Dimensions: 1254×1254, 8-bit RGB PNG
- Prompt:

> Use case: stylized-concept. Asset type: source master for a production iOS racing-game terrain PBR atlas. Create a square, edge-to-edge, orthographic top-down material featuring cool fractured granite, compact gravel, dark soil, mountain grass, and tiny old snow in crevices. Make it seamless-looking, with even macro variation and no central focal object. Use diffuse neutral studio light with minimal directional shadow and a production-polished stylized-realism treatment in an authored low-poly language. No road markings, cars, buildings, horizon, sky, text, logo, watermark, dramatic baked shadows, perspective, obvious repeating stamps, or isolated props.

### Desert Circuit

- File: `desert_terrain_source.png`
- Built-in source ID: `exec-0aaeffee-34be-4348-8b39-15377b0c2639`
- SHA-256: `062c6cc3a963d7c161947af2ed913fd450e007af469fecf177432694792bab54`
- Dimensions: 1254×1254, 8-bit RGB PNG
- Prompt:

> Use case: stylized-concept. Asset type: source master for a production iOS racing-game terrain PBR atlas. Create a square, edge-to-edge, orthographic top-down material featuring red sandstone, ochre sand, cracked clay, gravel, and dry scrub. Make it seamless-looking, with even macro variation and no central focal object. Use diffuse neutral studio light with minimal directional shadow and a production-polished stylized-realism treatment in an authored low-poly language. No road markings, cars, buildings, horizon, sky, text, logo, watermark, dramatic baked shadows, perspective, obvious repeating stamps, or isolated props.

## Deterministic processing contract

`Scripts/build_racing_environment_pbr_maps.swift` version 1.0.0 validates each complete source file against the fixed SHA-256 above before decoding it. It then applies this fixed recipe:

1. Decode into an 8-bit sRGB RGBA buffer with CoreGraphics.
2. Use the centered 1200×1200 crop at source origin `(27, 27)`.
3. Build a 1024×1024 atlas from four 512×512 quadrants in top-left coordinate order: primary terrain, secondary terrain, transition, and track-specific decal.
4. Apply fixed wrapped offsets/scales and a 36-pixel symmetric opposite-edge blend. The two pixels at each pair of opposite boundaries resolve to the same weighted sample, reducing wrap seams without an authored focal stamp.
5. Apply fixed track/quadrant color recipes, then derive tangent-space normals with wrapped per-quadrant gradients and derive scalar roughness with a fixed luminance/contrast curve.
6. Export opaque 8-bit RGBA PNGs. Base color embeds sRGB and is loaded with RealityKit `.color`; normal and roughness embed linear sRGB and are loaded with `.normal` and `.scalar`. Roughness is replicated identically to R, G, and B and alpha is 255.

The source-to-atlas relationship, quadrant content, output names, semantics, dimensions, decoded-byte budget, and pending/actual derived hashes are machine-readable in `WatchCarRacer/iOS/Resources/RacingEnvironment3D/RacingEnvironmentAssetManifest.json`. Null derived hashes mean “pending SG3 generation”; they are not placeholder hashes.

`Scripts/build_racing_environment_usd.swift` version 1.1.0 has separate `build`, `validate`, and `package` modes. Ridge, cliff, and mesa bodies are authored as closed volumes with deterministic ground skirts; Alpine snow accents use the runtime's solid mountain caps instead of an open USD sheet. Package mode first requires byte-exact generated USDA, sets every USDA modification time to `2026-08-30T00:00:00Z`, and invokes `/usr/bin/usdzip --checkCompliance` from the output directory with `TZ=UTC` and relative input/output basenames. This avoids embedding temporary absolute paths or varying timestamps and makes the stored, compliant one-layer USDZ packages byte-for-byte reproducible.

Build and validate with:

```sh
swift Scripts/build_racing_environment_usd.swift build <output-directory>
swift Scripts/build_racing_environment_usd.swift validate <output-directory>
swift Scripts/build_racing_environment_usd.swift package <output-directory>

swift Scripts/build_racing_environment_pbr_maps.swift build \
  docs/assets/sources/racing-environment \
  <output-directory> \
  WatchCarRacer/iOS/Resources/RacingEnvironment3D/RacingEnvironmentAssetManifest.json

swift Scripts/build_racing_environment_pbr_maps.swift validate \
  docs/assets/sources/racing-environment \
  <output-directory> \
  WatchCarRacer/iOS/Resources/RacingEnvironment3D/RacingEnvironmentAssetManifest.json
```
