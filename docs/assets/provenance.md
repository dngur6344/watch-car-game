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
