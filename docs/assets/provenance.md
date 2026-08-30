# Production PNG provenance

All production art in this table was created for Watch Car Racer on 2026-08-24 with Codex's built-in `image_gen` tool. No stock image, external asset pack, trademark, logo, real vehicle reference, or third-party source image was supplied. The project owner directed the generation and may use the outputs subject to the applicable OpenAI service terms; no separate third-party license or attribution is required. Rejected draft generations are not project resources and are not listed below.

The selected generated sources were normalized mechanically with Apple CoreGraphics and ImageIO: resize or aspect-fit padding onto the locked canvas, 8-bit sRGB RGBA PNG export, and alpha preservation. Vehicle sources additionally used deterministic pixel separation of neutral-white body pixels into a white-alpha paint mask; the complementary authored glass, lights, wheels, trim, and highlights became `details`, while source alpha supplied a subdued aligned `shadow`. No shape was redrawn and no runtime dependency was added.

## Prompt contract

Every selected prompt included this shared direction:

> Original, brand-neutral, premium stylized 2.5D mobile racing game art for a neon-dusk expressway. Fixed high three-quarter/top-down roadway camera, consistent upper-left key light with restrained cyan/magenta dusk rim light, crisp readable silhouette and coherent materials. No text, logos, badges, brands, trademarks, watermarks, numbers, characters, checkerboard, frame, resemblance to Crossy Road, or resemblance to a real vehicle/product.

Cutout prompts required a genuinely transparent background, generous padding, and an unclipped contact shadow. Vehicle and traffic prompts additionally required a high rear three-quarter/top-down roadway camera with the front/nose at the top edge (`+Y`), the rear at the bottom, and the vehicle driving away from the viewer.

The family-specific prompt requests were:

- `P-RALLY`: compact original rally hatch; short wheelbase, playful wide fenders, small roof scoop, restrained rear spoiler; neutral white paint source suitable for aligned shadow/paint/details separation.
- `P-GT`: low original GT coupe; flowing teardrop cabin, broad rear shoulders, subtle endurance-style aero channels; neutral white paint source suitable for aligned shadow/paint/details separation.
- `P-ANGULAR`: compact original angular performance wedge; faceted panels, squared rear haunches, blade-like spoiler; neutral white paint source suitable for aligned shadow/paint/details separation.
- `P-TRAFFIC-SEDAN`: modest original four-door commuter sedan in desaturated warm amber with a simple rounded cabin and practical narrow stance.
- `P-TRAFFIC-WAGON`: modest original compact delivery wagon in muted teal-gray with a tall practical cabin and squared cargo silhouette.
- `P-BARRIER`: one original modular reinforced expressway barrier, low wide sculpted concrete body, dark rubber impact corners, thin cyan reflective inserts, no markings.
- `P-LANE`: one elongated warm-ivory retroreflective lane dash with subtle wear, faint rough edge, and restrained dusk glint; flat and vertical.
- `P-DECAL`: an original nonverbal forward-motion road decal formed by nested mint/cyan chevron ribbons with tasteful worn paint texture; flat, symmetrical, and pointing `+Y`.
- `P-LIGHT`: one original slim solar expressway light pylon with a faceted dark-metal mast, small angled cyan/magenta light fins, and compact weighted foot.
- `P-PALM`: one original wind-shaped ornamental palm-like roadside plant with simplified midnight-teal fronds, restrained dusk rim light, and compact geometric planter.
- `P-MARKER`: one original abstract marker monument with a low faceted dark-stone base and two floating offset neon-glass slats; no letters, numbers, arrows, or recognizable road sign.
- `P-SKY`: wide original neon-dusk panorama from midnight violet to muted coral/magenta, layered atmospheric bands, distant abstract city silhouettes, restrained hazy sun, horizon in lower third, no foreground road.
- `P-ASPHALT`: square orthographic top-down seamless dark expressway asphalt, fine aggregate, subtle longitudinal wear, faint cool dusk bounce, uniform density, no markings or baked perspective.

## Production files

| Production PNG | Family | Prompt | Selected built-in source | Mechanical modification | SHA-256 |
| --- | --- | --- | --- | --- | --- |
| `Backgrounds/asphalt.png` | background.road | P-ASPHALT | `exec-327d1cad-0217-4a72-bc3e-311f0d6583e2.png` | resized to 1024×1024; sRGB RGBA export | `3bccf656882f78b7bee86d1c7fd1e9bb5ac92e480eb82b8d4650ca053b56fb43` |
| `Backgrounds/sky_horizon.png` | background.sky | P-SKY | `exec-953f6564-18a2-419e-9a1b-9ec00cb0ff42.png` | resized to 2048×1024; sRGB RGBA export | `f12a09067693263ac494421f8db50e237280aed421ceff04c66f467c4768b7fb` |
| `Environment.atlas/lane_worn.png` | environment.lane | P-LANE | `exec-e6d57af4-8972-4caf-bf42-035dd5b637e7.png` | resized to 64×256; alpha preserved | `fc21c06a70c19f74e764cced0998b346824e46acf409de4ee6f3f63648c12647` |
| `Environment.atlas/road_decal_chevrons.png` | environment.road-decal | P-DECAL | `exec-cf01af85-f510-4aed-95b9-644ab55ab789.png` | aspect-fit to 256×256; alpha preserved | `3436b6906e23e445365b7f99fb77f9c2db942cb84038e16633100d307dff174b` |
| `Environment.atlas/roadside_light.png` | environment.roadside.light | P-LIGHT | `exec-b3182edc-bc2a-4d72-89ff-9210ed6045fc.png` | aspect-fit to 256×512; bottom-center contract | `a0825e278de1b1971fe2f182f7597befa649b9c9bea1b3eaf1ccec013ed72c8d` |
| `Environment.atlas/roadside_marker.png` | environment.roadside.marker | P-MARKER | `exec-398a6e30-83e9-421c-863f-694e9a80d098.png` | aspect-fit to 384×512; bottom-center contract | `9f908c9c6cbe65e6f60216d2106667230d6a8e18b7c89065ce65eaacefba181c` |
| `Environment.atlas/roadside_palm.png` | environment.roadside.vegetation | P-PALM | `exec-db4a9d78-a0b9-4770-b3bf-dd082728b2e2.png` | aspect-fit to 384×512; bottom-center contract | `cb078a7f0ad588fb0a27b21d750611a4ba71dc010b3e4049d52af5068ef0358f` |
| `Obstacles.atlas/barrier_modular.png` | obstacle.barrier | P-BARRIER | `exec-37934454-fe4c-4ce8-8246-808ceb685070.png` | resized to 512×256; alpha preserved | `92d4f820556705b3fe7df6d4923ab1cd6621e7749074acd7b663036559b918f9` |
| `Obstacles.atlas/traffic_sedan.png` | obstacle.traffic.sedan | P-TRAFFIC-SEDAN | `exec-04221caf-ad23-493f-b72d-41457b2e3af1.png` | resized to 320×480; alpha preserved | `48c5e3b751adf2de6566d96dea72b4e4ceb31ecf98042edb5b867e3c89162424` |
| `Obstacles.atlas/traffic_wagon.png` | obstacle.traffic.wagon | P-TRAFFIC-WAGON | `exec-2d25bac0-790e-46db-9d6a-5ba3e6a39f72.png` | resized to 320×480; alpha preserved | `ba6a9c32a11a377157a051ad3dbbf6efe5bce7498d1332a9b8830f9dcb6b898a` |
| `Vehicles.atlas/angular_details.png` | vehicle.angular.details | P-ANGULAR | `exec-e1b482d0-50e8-488d-9600-45f60c037d3d.png` | 384×576 complementary authored-details alpha; 8/12px safety inset | `de1c8f37a2c3e87e8e53883b0e071140c9e39a071c50d89047bf01d740a3de3b` |
| `Vehicles.atlas/angular_paint.png` | vehicle.angular.paint-mask | P-ANGULAR | same as above | 384×576 neutral-white paint mask; 8/12px safety inset | `89f0b7ec9362d778d829bcb4e82e41a33ec662710a1dbcedcc4def54e6756c10` |
| `Vehicles.atlas/angular_shadow.png` | vehicle.angular.shadow | P-ANGULAR | same as above | 384×576 aligned subdued source-alpha shadow; 8/12px safety inset | `646dc6e8e1f75fb064f661ef2100a2c68b1962bbbb0cad3ec43ec2ee85f5ee57` |
| `Vehicles.atlas/gt_details.png` | vehicle.gt.details | P-GT | `exec-7836e2a3-b6a6-447d-a5f8-b3cffb9642fd.png` | 384×576 complementary authored-details alpha; 8/12px safety inset | `1ead832f1182aba024bca0029c90b5dfe9cb2a15f7266de98efc40ddb7a91137` |
| `Vehicles.atlas/gt_paint.png` | vehicle.gt.paint-mask | P-GT | same as above | 384×576 neutral-white paint mask; 8/12px safety inset | `9ef49f1f3129ed5c0c36cff1d47b36174b48ee542d28ee141bd814b323098ff5` |
| `Vehicles.atlas/gt_shadow.png` | vehicle.gt.shadow | P-GT | same as above | 384×576 aligned subdued source-alpha shadow; 8/12px safety inset | `7aefb94b7c3efc59bd5cabb2ed0e1191578c0aae5b54d1e65ffedd0f296d8fda` |
| `Vehicles.atlas/rally_details.png` | vehicle.rally.details | P-RALLY | `exec-26aea5ed-3036-4b9c-89e4-72717e92790d.png` | 384×576 complementary authored-details alpha; 8/12px safety inset | `6b135621e4ca31acfbfa7ec8d0d05598687676abf8e0e8e9f4158a9d2ee33024` |
| `Vehicles.atlas/rally_paint.png` | vehicle.rally.paint-mask | P-RALLY | same as above | 384×576 neutral-white paint mask; 8/12px safety inset | `40254d7aa89059956a4c350a61c0ca077a50447e4826d757a9623bc5c5ec28c6` |
| `Vehicles.atlas/rally_shadow.png` | vehicle.rally.shadow | P-RALLY | same as above | 384×576 aligned subdued source-alpha shadow; 8/12px safety inset | `204f476d221bb6a03d5a7b068cc335e84b18649efe86567b1b799f98a4914332` |

The selected source files remain in the built-in tool's generated-image store for audit. Every runtime-referenced final PNG is copied into `WatchCarRacer/iOS/Resources`; the application never references the generated-image store.

## Presentation kit (2026-08-28)

The eight presentation resources were created with Codex's built-in `image_gen` tool and deterministic Apple CoreGraphics/ImageIO processing. The three supplied screenshots in `.woohyuk/design-references` were used only as mood, hierarchy, and composition references; they were not edit targets and no pixels were copied from them. No stock image, external asset pack, logo, trademark, real vehicle reference, or third-party runtime dependency was used.

### Built-in prompts and selected sources

`P-PRESENTATION-HUB`:

> Create an original cinematic neon-sunset expressway leading toward a luminous abstract portal-like horizon for a premium iPhone landscape game hub. Use a wide road-first one-point perspective, wet-dark asphalt, subtle guardrail light strips, distant original skyline silhouettes and palms, with generous low-detail UI-safe margins. Use the inspected Expressway Portal screenshot only as a style/composition reference, not an edit target. Environment only: no vehicle, people, text, letters, numbers, UI, buttons, controls, icons, logos, brands, trademarks, recognizable products, watermark, border, frame, checkerboard, signature, start grid, text-like road markings, or baked interface shapes.

- Selected built-in source: `/Users/woohyuk/.codex/generated_images/01a047d5-e63c-76c1-868b-402bcb745f50/exec-14d89caa-3dc8-45dd-9623-bf5a4ebae4c3.png`

`P-PRESENTATION-MAINTENANCE`:

> Create an original cinematic wet neon pit-lane workshop environment with a large empty central staging floor for an overlaid vehicle hero. Use an open-sided night workshop flowing into a rain-dark pit lane, charcoal concrete, brushed dark metal, restrained cyan work lights, magenta dusk/rain glow, and a soft distant original skyline. Use the inspected Pit Lane and Precision Workshop screenshots only as style/composition references, not edit targets. Preserve broad empty central space and UI-safe left/right margins. Environment only: no vehicle, lift, tool cart, people, text, letters, numbers, UI, controls, icons, logos, brands, trademarks, recognizable products, watermark, border, frame, checkerboard, signature, readable signs, or baked interface panels.

- Selected built-in source: `/Users/woohyuk/.codex/generated_images/01a047d5-e63c-76c1-868b-402bcb745f50/exec-309bed0f-f7dc-46e2-ad6d-42ba983b0df3.png`

`P-PRESENTATION-RALLY`:

> Create one original brand-neutral compact Rally Hatch as a premium stylized-realistic 3D hero with neutral-white exterior paint: short wheelbase, playful wide bolt-free fenders, compact muscular stance, small centered roof intake, restrained integrated rear roof spoiler, practical five-door cabin, original slim angular lamps, and no resemblance to a real production vehicle. Use a fixed front three-quarter camera from slightly above, nose toward lower-left, body toward upper-right, whole vehicle plus soft authored ground shadow visible on a square canvas with at least 9% genuinely transparent padding. No environment, text, letters, numbers, logo, badge, emblem, grille mark, brand, trademark, livery, decal, watermark, border, frame, checkerboard, or signature.

- Selected built-in source: `/Users/woohyuk/.codex/generated_images/01a047d5-e63c-76c1-868b-402bcb745f50/exec-bf629493-d6f7-4f5a-8037-5896dd5baf46.png`

`P-PRESENTATION-GT`:

> Create one original brand-neutral low GT Coupe as a premium stylized-realistic 3D hero with neutral-white exterior paint: elegant two-door grand tourer, long low hood, flowing teardrop cabin, broad rear shoulders, subtle endurance-inspired side aero channels, restrained integrated rear lip, original slim horizontal lamps, and no resemblance to a real production vehicle. Use the same fixed front three-quarter camera, alignment, square canvas, authored ground shadow, and genuinely transparent padding as the Rally hero. No environment, text, letters, numbers, logo, badge, emblem, grille mark, brand, trademark, livery, decal, watermark, border, frame, checkerboard, or signature.

- Selected built-in source: `/Users/woohyuk/.codex/generated_images/01a047d5-e63c-76c1-868b-402bcb745f50/exec-04014b78-1197-4f52-bf49-46fdcb5698a7.png`

`P-PRESENTATION-ANGULAR`:

> Create one original brand-neutral Angular Performance vehicle as a premium stylized-realistic 3D hero with neutral-white exterior paint: compact futuristic wedge, crisp faceted body planes, low polygonal canopy, squared muscular rear haunches, sharply chamfered wheel arches, geometric triangular intake language, thin blade-like rear spoiler, original narrow blade lamps, and no resemblance to a real production vehicle. Use the same fixed front three-quarter camera, alignment, square canvas, authored ground shadow, and genuinely transparent padding as the other heroes. No environment, text, letters, numbers, logo, badge, emblem, grille mark, brand, trademark, livery, decal, watermark, border, frame, checkerboard, or signature.

- Selected built-in source: `/Users/woohyuk/.codex/generated_images/01a047d5-e63c-76c1-868b-402bcb745f50/exec-47cb1da1-2713-4be3-8af3-5b2e860deeb0.png`

Rejected built-in paint/details edits that baked checkerboard pixels were not copied, used for processing, or referenced by the application.

### Deterministic processing

`Scripts/process_presentation_assets.swift` accepts explicit source and output paths. Backgrounds are high-quality resized to 1672×941 and exported as opaque-pixel, 8-bit sRGB RGBA PNGs. Each accepted transparent vehicle master is high-quality resized to a 1024×1024 sRGB RGBA canvas before separation.

For vehicle separation, pixels seed the paint classification only when source alpha is at least 0.55, luminance is at least 0.38, absolute RGB chroma is at most 0.30, and relative chroma is at most 0.44. Eight-connected components are retained when they contain at least 6,000 pixels, or contain at least 2,000 pixels with a width-to-height ratio of at least 4.0 so authored wide spoilers remain paint while isolated wheel highlights and ground-shadow strips remain fixed details. A two-pixel color-constrained fringe preserves antialiased paint edges. Selected paint pixels become white premultiplied RGB with their source alpha; the details/shadow layer receives the exact complementary source pixels. An eight-pixel safety border is cleared after separation. The paired layers therefore share the same canvas and pivot and never overlap in alpha.

The same script composes the three aligned pairs with all eight catalog colors into `docs/assets/presentation-contact-sheet.png`. This 3×8 evidence confirms paint changes while glass, lights, tires, wheels, trim, interior details, and authored ground shadows remain unmodified.

### Production files

| Production PNG | Family | Prompt | Mechanical modification | SHA-256 |
| --- | --- | --- | --- | --- |
| `Presentation/hub_expressway_portal.png` | presentation.background.hub | P-PRESENTATION-HUB | 1672×941; 8-bit sRGB RGBA opaque export | `64257b974b1d07fb6a8ae2faefc0537b4fbff02570af8d4fdacda2ebe0436317` |
| `Presentation/maintenance_pit_lane.png` | presentation.background.maintenance | P-PRESENTATION-MAINTENANCE | 1672×941; 8-bit sRGB RGBA opaque export | `fba45165b5a16f0968165474730c5cf1ff627c28080f8f2a44042407162354c5` |
| `Presentation/rally_hero_paint.png` | presentation.vehicle.rally.paint-mask | P-PRESENTATION-RALLY | 1024×1024 aligned pure-white alpha paint split | `27830cc73213aaf048cbdfa968f6a2b95a3f0d0e00b8fcb8505cc2569447f930` |
| `Presentation/rally_hero_details_shadow.png` | presentation.vehicle.rally.details-shadow | P-PRESENTATION-RALLY | 1024×1024 complementary fixed details/shadow split | `0bb9a59c950ce2097336c028fccae820811fd963d1f6217564f89956da01229d` |
| `Presentation/gt_hero_paint.png` | presentation.vehicle.gt.paint-mask | P-PRESENTATION-GT | 1024×1024 aligned pure-white alpha paint split | `196a3aeff5f276517e0cc986b6d08c7d0ecd11e5b1903ef25c9681b31fbef144` |
| `Presentation/gt_hero_details_shadow.png` | presentation.vehicle.gt.details-shadow | P-PRESENTATION-GT | 1024×1024 complementary fixed details/shadow split | `dc0ba9852d81b003f2afe847c0f688853e4a848133a3fe829b1ecfc4593c0f9f` |
| `Presentation/angular_hero_paint.png` | presentation.vehicle.angular.paint-mask | P-PRESENTATION-ANGULAR | 1024×1024 aligned pure-white alpha paint split | `630fcc807fa702df9e763c0c707ff3493a793bafe67967077024672d50e9f473` |
| `Presentation/angular_hero_details_shadow.png` | presentation.vehicle.angular.details-shadow | P-PRESENTATION-ANGULAR | 1024×1024 complementary fixed details/shadow split | `aa710880cde0ebafeedb8caa6e1c4649ef1baaa674e735b08cca774a0925714c` |

Contact-sheet evidence SHA-256: `749ad4d843e3d0e0ace9eee101db51436f21aeebf30bc364bc3b84c6bda8a1f4`.

## Project-original audio kit (2026-08-29)

All 15 production WAV files were created specifically for Watch Car Racer on 2026-08-29 by repository tool `Scripts/build_original_audio_assets.swift` version `1.0.0`. The tool runs offline with first-party Swift/Foundation capabilities and fixed seeds. It layers original oscillator voices, deterministic seeded noise, filters, envelopes, stereo phase offsets, and deterministic loop-boundary transitions, then removes DC offset, peak-normalizes, quantizes, and writes 48,000 Hz signed 16-bit little-endian PCM WAV files. No recording, stock sound, third-party sample, model-generated audio, external download, third-party library, or runtime synthesis is used.

Source declaration: repository-authored deterministic oscillator, noise, and envelope recipes; no external source material. License declaration: project-original; all rights are held by the Watch Car Racer project owner. No third-party license or attribution is required. The complete per-role recipe text, format, duration, channel count, loop flag, authoring version, and shipped hash are also machine-readable in `WatchCarRacer/iOS/Resources/Audio/AudioAssetManifest.json`.

The six driving loops combine role-specific motor harmonics or shaped noise with periodic modulation. The two stereo route ambiences combine low drones, independent seeded air layers, and channel-specific shimmer/metallic partials. The seven one-shots use bounded attack/release or exponential decay envelopes around synthesized ticks, bass/impact modes, chirps, and tonal/noise sweeps. Loop roles receive a deterministic 10 ms boundary tile plus entry/exit crossfades before DC removal and normalization; the first and last 10 ms windows therefore remain aligned after PCM quantization.

| Production WAV | Role | Recipe summary | SHA-256 |
| --- | --- | --- | --- |
| `Audio/engine_idle_loop.wav` | `engine_idle_loop` | 55/110/165 Hz motor harmonics, 2 Hz pulse, low-passed mechanical noise | `e8d721b1a7d4f45deb0b04425a78119e36ca75cecaf652fd1e0f2e3c3f9e4995` |
| `Audio/engine_mid_loop.wav` | `engine_mid_loop` | 90/180/270 Hz motor harmonics, 4 Hz pulse, mechanical noise | `98f0c790424298e3ef56e5c5446fea13cc5d1020527e3b4142acdbc926ffa57f` |
| `Audio/engine_high_loop.wav` | `engine_high_loop` | 140/280/420/700 Hz motor harmonics and bright mechanical noise | `4d84c209fb8753523dbbc467b776801fbd70d43b227717b1193b2e81eadd0cf2` |
| `Audio/road_loop.wav` | `road_loop` | low-passed surface noise with 34/68 Hz road rumble | `963e08db686dec36ed194b1aef448bc85fcec7e986113207f35d2c41c68d85f3` |
| `Audio/wind_loop.wav` | `wind_loop` | broadband and high-pass air noise with slow gust modulation | `f58ecee5dc529a77fdffe73f280fac24eae9b17846b1c81937a964eb21d80564` |
| `Audio/tire_scrub_loop.wav` | `tire_scrub_loop` | high-pass scrub noise with 620/930 Hz friction resonances | `4df6bbe15b5fa5c14deefd2bb08598b78c8f9baf236c15d3400e000608ef74f0` |
| `Audio/near_miss_whoosh.wav` | `near_miss_whoosh` | fast air-noise envelope and descending tonal edge | `8cb847d61a9d7429922e672268fd88965967da39efff4f7e9adfbeb7cddb7686` |
| `Audio/collision_impact.wav` | `collision_impact` | seeded transient with decaying 43/86 Hz impact modes | `b679d626612897bab768328e48ac22a83d8089ee236dea67deaf148add616d0c` |
| `Audio/countdown_tick.wav` | `countdown_tick` | 1320/1980 Hz tick with short seeded attack | `266489475bdbc72bd91eaf2930cb20c3f1e50431151f562298338c6bd4dcaede` |
| `Audio/go_bass_hit.wav` | `go_bass_hit` | descending 88-to-42 Hz bass hit and transient layer | `319325b51ebcd5894dc9434cbaa8e8e0ef270b80c3658f786809f8c0dd79ab14` |
| `Audio/hub_ambience_loop.wav` | `hub_ambience_loop` | stereo 42/84 Hz drone, shimmer, and independent air layers | `14448e84aa02d904b642e85b7f81bc78a9be3a05ce08c5c1059d9f5f2c4154a5` |
| `Audio/maintenance_ambience_loop.wav` | `maintenance_ambience_loop` | stereo 48/96 Hz drone, metallic partials, and independent air layers | `fba2ce59fc80da6647a36bc8f0fddea11138519048d302bc4b7ead7b2dccbcf4` |
| `Audio/vehicle_select.wav` | `vehicle_select` | 760/1140 Hz confirmation chirp and click | `8e00f990ee0bf156167ecfa208bbaea594af8b89734eec5cbf505c8d70b7686a` |
| `Audio/color_select.wav` | `color_select` | 1040/1560 Hz color chirp and click | `3a0091c4d259985d276a63f916118090d80a88cfa178ddc85ddc2c48d10301e0` |
| `Audio/drive_transition.wav` | `drive_transition` | rising 190-to-780 Hz tonal sweep and air-noise layer | `05f55d93e7d0749d9f820af522e9fd65bf50ce2a336c55189ecfa9c55f744ddb` |

## Project-original RealityKit 3D/PBR production kit (2026-08-30, revision 2)

The racing view's production 3D kit is entirely project-authored and brand-neutral. Repository tool `Scripts/build_production_racing_usd.swift` revision 2 deterministically creates three distinct hero vehicles, a lower-complexity traffic sedan, and a modular track barrier. The Rally, GT, and Angular vehicles have independent lofted body profiles, canopy proportions, aero treatments, rear-light signatures, wheelbases, wheel diameters, and accent colors. Hero wheels include ten spokes, hubs, brake discs, calipers, and separate tires; hero bodies include named paint surfaces, fender volumes, mirrors, splitters, side skirts, lamps, diffusers, exhausts, vents, and vehicle-specific spoilers. The traffic asset retains the same material language with fewer wheel and body details for repeated rendering. Every root records its project-original license, authoring tool, asset role, and production revision in USD custom data.

`/usr/bin/usdchecker` validates every editable USDA source, and `/usr/bin/usdzip --checkCompliance` stores each source without external dependencies in its runtime USDZ. The five runtime packages total less than 512 KiB and each package remains below 128 KiB. The app loads the selected vehicle's distinct USDZ, applies the chosen catalog color only to named paint and mirror surfaces, uses the lightweight traffic/barrier assets for obstacles, and retains in-code procedural geometry as a safe per-asset fallback.

`Scripts/build_racing_pbr_maps.swift` deterministically derives the asphalt normal and roughness maps from the existing project-owned `Backgrounds/asphalt.png`. It uses CoreGraphics/ImageIO only, applies a wrapped Sobel-style height gradient for the tangent-space normal map and an aggregate-aware high-roughness curve for the scalar map, then writes 1024×1024, 8-bit sRGB RGBA PNGs. No stock model, downloaded texture, third-party asset pack, recognizable production vehicle, or external runtime dependency is used.

| Production asset | Role | Source and processing | SHA-256 |
| --- | --- | --- | --- |
| `Racing3D/rally_racer.usda` | editable Rally hero source | short-wheelbase loft, rally wing, roof scoop, block lamps, hero wheel/brake detail | `94e23ae4da95829c7f086c228a933008f437be2f94cbaf5bbaf058c6b9a51f13` |
| `Racing3D/rally_racer.usdz` | RealityKit Rally hero | compliant stored USDZ produced from the authored USDA | `753b0ca8836d3d3e0851189620b06afca8eaa1a306c638af458a019b1dba90e3` |
| `Racing3D/gt_racer.usda` | editable GT hero source | long low loft, ducktail, continuous rear light, staggered hero wheels | `2cb6bbdc27dbecd520964342229c4dad8c05f3260162eae3c6d55f965771c970` |
| `Racing3D/gt_racer.usdz` | RealityKit GT hero | compliant stored USDZ produced from the authored USDA | `248920909bd2bbbcecf699893ea69faf54186fd7864ef327ddb41541095b73e0` |
| `Racing3D/angular_racer.usda` | editable Angular hero source | faceted wedge loft, blade wing, segmented lamps, broad rear wheels | `8de9be3e5949d626c75fde413f1c7fa43c7d49df8a0e0dc38f119fdece950bd6` |
| `Racing3D/angular_racer.usdz` | RealityKit Angular hero | compliant stored USDZ produced from the authored USDA | `6398420dc8311c92fefc57b8c517f490b0fcc72a6e458c54efe01aa9f7b67248` |
| `Racing3D/traffic_sedan_3d.usda` | editable repeated-traffic source | lower-complexity sedan loft and wheels with production materials | `fa46f51149f3f39ba92859bdc9154a60dad6bb5afe8dbb5ff8c4822ea4c76f03` |
| `Racing3D/traffic_sedan_3d.usdz` | RealityKit traffic vehicle | compliant lightweight stored USDZ | `1fdb141d516f08efb9dc8f80f32047b4f30467a637397cf876e75546245a008d` |
| `Racing3D/track_barrier.usda` | editable obstacle source | five-panel modular barrier, feet, alternating materials, emissive reflectors | `2d5009eea05facd538fbf364a4e1a9c7a7618b70593df60f0b43bc68c3feb68f` |
| `Racing3D/track_barrier.usdz` | RealityKit barrier | compliant lightweight stored USDZ | `911fc70d5e295cbd442a721af73d2b3e9a6369772aea24d075120833e36c57ea` |
| `Racing3D/asphalt_normal.png` | asphalt tangent-space normal | deterministic wrapped gradient derived from `Backgrounds/asphalt.png` | `c978c6d71292bb1bf012bd6e527cf74fe4ba758177fab50ad53f3634b8d9f571` |
| `Racing3D/asphalt_roughness.png` | asphalt scalar roughness | deterministic aggregate-aware curve derived from `Backgrounds/asphalt.png` | `44bbd02430d7f5ca8b3f9f9830689c6203ec7814542e6a8b4a31386667ed8509` |

Generator SHA-256: `f41480ccc68f019f2525de28d94de58fa80eb409388fd1091e97f4d8d2f51f5f`.
