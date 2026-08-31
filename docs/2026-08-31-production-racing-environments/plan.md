---
title: "출시 수준의 스타일라이즈드 자연 환경 고도화"
status: implemented
created: 2026-08-30
updated: 2026-08-31
implemented_at: 2026-08-31
target_repo: "/Users/woohyuk/Desktop/watch-car-racer"
goal_size: large
feature_slug: "production-racing-environments"
---

# 출시 수준의 스타일라이즈드 자연 환경 고도화

## Goal

Ocean Drive, Alpine Pass, Desert Circuit의 자연 배경을 기본 도형 조합에서 프로젝트 고유의 프리미엄 스타일라이즈드 3D 환경으로 교체한다. 전경·중경·원경, PBR 지형, 결정론적 자연물 군집, 연속 hero vista, 날씨 반응과 적응형 품질을 결합하되 기존 게임 로직과 조향 계약을 변경하지 않고 iPhone 13급 baseline 60FPS를 목표로 한다.

## Assumptions

- 형태와 실루엣은 스타일라이즈드 로우폴리로 유지하지만 primitive cone/box/cylinder가 그대로 읽히지 않도록 authored profile, 비대칭 능선, 침식면과 군집 실루엣을 사용한다. 표면 재질, 조명과 접촉 그림자는 스타일라이즈드 리얼리즘 수준으로 구성한다.
- 생성 이미지는 authoring-time source로만 사용한다. 선택 원본과 prompt/tool/source ID/source SHA-256/derived SHA-256을 `docs/assets/sources/racing-environment/`와 manifest/provenance에 보존하고, 저장소 스크립트가 이를 color용 sRGB atlas와 normal/roughness용 linear data map으로 결정론적으로 후처리한다. source master와 USDA는 app target에서 제외한다.
- 날씨 상호작용은 PBR material set, decal, bounded particle, rigid vegetation sway와 depth haze로 구현하며 유체·연성체 시뮬레이션과 runtime asset generation은 사용하지 않는다.
- adaptive quality의 baseline은 iPhone 13급 60FPS 목표이고 enhanced는 최신 고성능 iPhone용이다. Simulator는 회귀와 강제 tier 검증 수단이며 실제 iPhone 13/최신 iPhone의 Release·Metal·열·메모리 검증 전에는 App Store 출시 성능을 승인하지 않는다.
- hero 연속성은 항상 화면 원경에 남는 track-specific vista와 주기적으로 통과하는 근거리 feature의 조합을 뜻한다. tunnel/arch가 매 순간 반복 노출되는 구조는 사용하지 않는다.
- 선택 트랙의 base pack과 필요 시 enhanced supplemental만 lazy load하고 cache는 현재 또는 최근 한 트랙으로 제한한다. 환경 Entity는 gameplay collision/input component를 갖지 않는다.
- production initial tier는 Low Power Mode가 꺼져 있고 thermal state가 nominal/fair이며 `ProcessInfo.physicalMemory >= 8 GiB`인 검증 후보 기기만 enhanced로 시작한다. Simulator·unknown·8GiB 미만 기기는 baseline이며 DEBUG launch argument에서만 tier를 강제할 수 있다. 6GiB 기기는 physical-device 검증 전까지 baseline을 유지한다.
- `47ebb7c`에서 추적·커밋된 `docs/screenshots/weather-clear.jpg`, `weather-rain.jpg`, `weather-fog.jpg`, `weather-storm.jpg`는 현재 문서 자산이다. 모든 subgoal에서 삭제·덮어쓰지 않고 exact SHA-256을 보존하며, 새 acceptance 캡처는 `.woohyuk/racing-environment-acceptance/` 아래에만 저장한다.

## Decisions

- 사용자 결정 1: 1A를 기반으로 하되 기본 도형 수준의 로우폴리가 아니라 프리미엄 스타일라이즈드 형태를 사용하고, 재질·조명·접촉 그림자는 1B에 가까운 품질로 만든다.
- 사용자 결정 2: 프로젝트 제작 USDZ 메시와 오리지널 생성 이미지/PBR 텍스처를 결합하는 2A 방식으로 에셋을 제작한다. 외부 유료 에셋 팩, third-party runtime dependency와 runtime network fetch는 추가하지 않는다.
- 사용자 결정 3: 3A 적응형 품질 등급을 사용한다. baseline composition은 모든 tier에서 유지하고 enhanced는 식생·근거리 LOD·접촉 그림자·날씨 밀도만 보강한다.
- 사용자 결정 4: runtime texture 예산은 A 방식으로 검증한다. 트랙당 12MiB는 base-level decoded payload 정적 계약으로 유지하고 per-environment Metal delta gate는 사용하지 않는다. full mipmap, active environment cache≤1 track과 game-route total Metal resident≤64MiB를 런타임 gate로 둔다.
- 트랙·날씨 선택, 차량 외형, 장애물, score/collision/spawn, steering packet과 Watch 연결 계약은 보존한다.

## Scope

- Ocean Drive: 해안 절벽·shoreline rock·palm/해안초·sea stack·ocean/headland와 해식 아치 cliff cove hero.
- Alpine Pass: 암벽 outcrop·pine 군집·gravel/grass transition·forest belt·설산 range와 tunnel frame 너머 주봉 hero.
- Desert Circuit: cactus/boulder 군집·sand/crack/gravel transition·canyon wall·mesa/plateau와 natural stone arch/twin mesa hero.
- 전경(약 0–55m), 중경(약 45–130m), 원경(약 110–240m)의 겹치는 3단 배경과 거리별 tint·saturation·roughness contrast·visibility를 통한 대기 원근.
- track tile의 논리 세그먼트 index와 fixed RNG를 통한 variant·scale·yaw·tint·cluster 배치, 인접 반복 회피, 재활용 seam 없는 LOD/parallax.
- 트랙별 terrain PBR atlas와 gravel/crack/sand/grass transition decal, 근거리 contact shadow, track-specific hero anchor.
- clear/rain/fog/storm에 따른 terrain/rock wetness, puddle, world-space depth haze, dust/spray, vegetation sway와 기존 SwiftUI overlay의 통합 강도 모델.
- baseline/enhanced resource·density·shadow·particle budget과 thermal/memory/지속 저프레임 시 주행 중 한 방향 downgrade.
- asset generator, manifest, provenance/SHA, iOS-only resource membership, unit/integration/visual/performance/memory acceptance.

## Out Of Scope

- `GameSimulation`, 장애물 spawn/collision/score/difficulty, 차량 physics와 camera gameplay semantics 변경.
- `ControllerMessages.swift`, WatchConnectivity, Watch 조향·보정·햅틱 계약 변경.
- 자연물에 gameplay collision을 추가하거나 tunnel/arch를 충돌 장애물로 만드는 작업.
- coastal의 grandstand, pit building, hotel과 허브·차량 정비 화면의 건축물 리디자인.
- photoreal renderer, Metal custom renderer, 실시간 ray tracing, 유체/연성체 simulation, third-party game engine 또는 external asset pack.
- 전체 차량·도로 아트 재제작, 새 progression·통화·트랙 unlock·날씨 gameplay modifier.
- 실제 iPhone/Apple Watch 검증을 Simulator 완료의 차단 조건으로 삼는 일. 단, App Store 출시 전 physical-device gate로 별도 남긴다.
- 구현 코드 리뷰. 이 계획의 `woohyuk-plan` 계획 검증만 수행한다.

## Current Evidence

- `WatchCarRacer/iOS/Game/RacingWorldView.swift`: `RacingTrack`, `RacingWeather`, `RacingEnvironmentSelection`, RealityKit resource/factory/update와 날씨 overlay가 집중되어 있다. 길이 12m 타일 18개를 216m 주기로 재활용하지만 논리 세그먼트 index는 보존하지 않는다.
- `WatchCarRacer/iOS/Game/RacingWorldView.swift`: asphalt만 base color/normal/roughness를 사용한다. shoulder와 광역 ground는 단색이고, 4개 고정 massif와 palm/pine/cactus/rock은 cone/box/cylinder/sphere 조합이다.
- `WatchCarRacer/iOS/Game/RacingWorldView.swift`: 자연물은 tile pool index modulus와 고정 좌표로 배치되어 216m마다 같은 위치·형태가 반복된다. 현재 날씨는 sunlight/IBL, asphalt roughness와 화면 공간 rain/fog/lightning 중심이며 자연물 wetness·depth haze·puddle·dust·sway는 없다.
- `WatchCarRacer/iOS/Resources/Racing3D/`: 프로젝트 제작 차량/traffic/barrier USDA·USDZ와 asphalt normal/roughness가 있으며, 자연 환경 전용 catalog와 pack은 없다.
- `Scripts/build_production_racing_usd.swift`, `Scripts/build_racing_pbr_maps.swift`: repository-owned deterministic USDA/USDZ와 CoreGraphics PBR 생성 선례가 있다.
- `WatchCarRacerTests/RacingWorldLayoutTests.swift`: 타일 연속성, track/weather 차이, authored SHA-256, USDZ 구조, PBR 형식, bundle membership와 RealityKit async load 검증 선례가 있다.
- `Scripts/measure_compiled_texture_memory.swift`, `Scripts/run_sg6_acceptance.sh`: texture·FPS·memory·presentation acceptance를 확장할 수 있는 선례가 있다.
- `docs/assets/provenance.md`: 생성 원본, 처리 방식, runtime asset SHA-256을 기록하는 기존 형식이 있다.
- `WatchCarRacer.xcodeproj/project.pbxproj`: Swift와 runtime resource를 수동 등록하며, 기존 계약은 USDA/source를 bundle에서 제외하고 USDZ/runtime PNG만 iOS target에 포함한다.
- Ralph 시작 시 Git 기준은 `main == origin/main == 47ebb7c`; 날씨 스크린샷 JPG 4개는 해당 커밋에 추적되어 있다. 보존할 SHA-256은 clear `ac76e02c5f8e76e1a6d6377896f9c444145e2bb8323dcac1800c1bdaf363a49c`, rain `1155364de7fc6d868cf7485f2859ad4045b84e83aeed9eaeb4331b1d4c4c280f`, fog `4c634384dc5d36db7a6c28c610f993b01fc025fa0c7f666d0829e642317d155d`, storm `971fe39922c3d413613f977dd245e63eafc4cb4b5417a0c1b80ed80d8a3fc81e`다.

## Architecture Boundaries

- `WatchCarRacer/iOS/Game/RacingEnvironmentCatalog.swift` (신규 후보): track profile, stable seed, distance layer, asset/variant/clearance/hero contract.
- `WatchCarRacer/iOS/Game/RacingEnvironmentLayout.swift` (신규 후보): logical segment, fixed RNG, deterministic cluster plan, LOD/parallax placement.
- `WatchCarRacer/iOS/Game/RacingEnvironmentAssetLibrary.swift` (신규 후보): 선택 트랙 USDZ/PBR lazy load, shared resource와 bounded cache.
- `WatchCarRacer/iOS/Game/RacingEnvironmentScene.swift` (신규 후보): foreground/mid/far/hero/weather root, terrain/decal/contact-shadow assembly와 update.
- `WatchCarRacer/iOS/Game/RacingEnvironmentWeather.swift` (신규 후보): wetness/fog/wind/dust/puddle/sway presentation state.
- `WatchCarRacer/iOS/Game/RacingEnvironmentQuality.swift` (신규 후보): baseline/enhanced budget, forced DEBUG tier, downgrade hysteresis.
- `RacingWorldView.swift`는 environment resources를 연결하고 기존 world lifecycle에서 새 scene assembler/updater를 호출한다. simulation·vehicle·obstacle·camera code는 환경 모듈로 이동하지 않는다.
- `WatchCarRacer/iOS/Resources/RacingEnvironment3D/` (신규 후보): 트랙별 base/enhanced USDA·USDZ, runtime PBR atlas와 manifest. source master는 `docs/assets/sources/racing-environment/`에만 둔다.

## Runtime Texture Contract

| 트랙별 runtime file | 용도와 atlas 영역 | encoding / RealityKit semantic | 크기 / decoded budget |
| --- | --- | --- | --- |
| `*_terrain_basecolor.png` | terrain base color와 gravel/crack/sand/grass/puddle color decal tile을 같은 atlas quadrant에 포함 | 8-bit sRGB RGBA / `.color` | 1024×1024 / 4MiB |
| `*_terrain_normal.png` | terrain과 decal의 tangent-space normal data | 8-bit linear-sRGB RGBA data map / `.normal` | 1024×1024 / 4MiB |
| `*_terrain_roughness.png` | terrain과 decal의 roughness scalar를 RGBA channel에 deterministic replicate | 8-bit linear-sRGB RGBA data map / `.scalar` | 1024×1024 / 4MiB |

- 별도 decal texture는 만들지 않는다. decal UV는 위 세 atlas의 예약 quadrant를 사용하므로 트랙별 3장·decoded 12MiB, 세 트랙 합계 36MiB 계약을 유지한다.
- manifest는 각 파일의 channel role, color encoding, RealityKit semantic, dimensions, source SHA와 derived SHA를 기록한다. loader와 test는 `.color/.normal/.scalar`를 명시적으로 사용하고 data map에 color gamma를 적용하지 않는다.
- bundle decoded-equivalent와 game-route resident를 별도 계약으로 관리한다. `measure_compiled_texture_memory.swift`가 기존 atlas/background/presentation뿐 아니라 `Racing3D` standalone PBR과 신규 `RacingEnvironment3D` 9장을 모두 family별로 열거하며, bundle 전체 hard cap은 112MiB·단일 dimension은 2048이다. 현재 약 57.11MiB, 기존 누락 Racing3D PBR 8MiB와 신규 환경 36MiB를 합친 예상치는 약 101.11MiB다.
- runtime은 현재 트랙의 3장만 lazy load하고 기존 loader와 같은 full mipmap 정책(`.allocateAndGenerateAll`)을 명시적으로 유지한다. 12MiB는 mipmap과 geometry를 포함하지 않는 base-level decoded payload 정적 계약이다. per-environment Metal delta는 측정하지 않으며 현재 game route의 총 `MTLDevice.currentAllocatedSize`는 64MiB 이하를 hard gate로 둔다. 다른 트랙으로 전환하면 이전 environment texture cache를 해제하고 한 트랙을 초과해 resident하지 않는다.

## Subgoals

- [x] SG1: 환경 catalog, 논리 세그먼트와 결정론적 layout 계약 추가
  - Outcome: 기존 track tile 화면 거리를 보존하면서 무한 코스의 stable logical segment를 얻고, 같은 track/seed/segment가 같은 layer·variant·cluster plan을 만든다.
  - Work: `RacingEnvironmentCatalog.swift`, `RacingEnvironmentLayout.swift`와 `RacingEnvironmentLayoutTests.swift`(모두 신규 후보)를 추가하고 `RacingWorldView.swift`의 기존 distance wrapper를 연결한다. `TrackTileState(distance, logicalSegmentIndex)`, SplitMix64 계열 fixed RNG, 3단 layer/hero/variant/road-clearance contract와 baseline/enhanced static budget을 정의한다. `project.pbxproj`에 신규 production/test Swift 파일을 각각 iOS app/test target으로 등록하고 기존 `RacingWorldLayout.trackTileDistance`는 `state.distance` wrapper로 유지한다.
  - Verify: `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' -only-testing:WatchCarRacerTests/RacingWorldLayoutTests -only-testing:WatchCarRacerTests/RacingEnvironmentLayoutTests test`. 같은 seed checksum, 다른 seed 차이, invalid travel sanitize, recycle 전후 logical index, 인접 동일 plan 회피, corridor clearance와 기존 distance 결과 동일성을 검증하고 `project.pbxproj` section test로 production/test source membership을 확인한다.
  - Depends on: None

- [x] SG2: 환경 USDZ/PBR authoring pipeline, manifest와 provenance contract 구축
  - Outcome: 선택 생성 원본을 고정한 뒤 트랙별 authored geometry와 PBR atlas를 repository-owned script로 반복 생성·검증할 수 있고, source와 runtime asset의 provenance가 연결된다.
  - Work: `Scripts/build_racing_environment_usd.swift`, `Scripts/build_racing_environment_pbr_maps.swift`, `WatchCarRacer/iOS/Resources/RacingEnvironment3D/RacingEnvironmentAssetManifest.json`, `docs/assets/sources/racing-environment/`(모두 신규 후보)를 추가한다. 각 트랙의 생성 원본을 선택·검수한 뒤 prompt, authoring tool, execution/source ID, source SHA, crop/edge-blend/atlas 처리와 derived SHA를 기록한다. generator는 비대칭 ridge/erosion profile, flattened material slots, named LOD/variant/hero entity와 custom metadata를 만들고, PBR script는 fixed source SHA를 검사한 뒤 Runtime Texture Contract에 따라 baseColor+decal은 sRGB, normal/roughness는 linear-sRGB data map으로 출력한다. `docs/assets/provenance.md` 형식을 확장한다.
  - Verify: 두 임시 디렉터리에서 generator/processor를 각각 두 번 실행해 derived output SHA 목록이 동일해야 한다. `/usr/bin/usdchecker`와 `/usr/bin/usdzip --checkCompliance`가 모든 USDA/USDZ를 통과해야 하며, source SHA 불일치, baseColor의 non-sRGB, data map의 non-linear encoding, manifest semantic mismatch와 잘못된 크기는 script가 실패해야 한다.
  - Depends on: SG1

- [x] SG3: Ocean·Alpine·Desert base/enhanced 자연 pack과 PBR atlas 제작
  - Outcome: 세 트랙의 authored base/enhanced pack, 전경·중경·원경용 자연물 변형, hero vista와 terrain transition PBR atlas가 manifest/provenance 계약을 만족한다.
  - Work: `RacingEnvironment3D`에 트랙별 base 1개와 enhanced supplemental 1개, 총 6개 USDA/USDZ 및 Runtime Texture Contract의 트랙별 3장을 생성한다. Ocean의 cliff/ocean/sea stack/cove, Alpine의 rock wall/pine/snow range/tunnel vista, Desert의 cactus/boulder/canyon/mesa/stone arch를 named contract로 제공한다. `RacingEnvironmentAssetTests.swift`(신규 후보), `project.pbxproj`, `measure_compiled_texture_memory.swift`, `provenance.md`를 갱신한다. 측정 script는 기존 atlas/background/presentation에 더해 기존 `Racing3D` PBR과 신규 environment map을 manifest 기반으로 빠짐없이 열거하고 family별·bundle 전체 decoded-equivalent를 보고한다.
  - Verify: asset test가 manifest↔provenance↔실제 SHA, required roots/LOD/variant/hero names, bounds와 road aperture, USDZ compliance, RealityKit async load, baseColor sRGB `.color`, normal linear `.normal`, roughness linear `.scalar`, iOS-only USDZ/PNG membership와 USDA/source 비번들을 검증한다. 트랙별 environment payload=12MiB, environment 전체=36MiB, bundle decoded-equivalent≤112MiB와 단일 dimension≤2048을 hard gate로 두고 family별 합이 전체 합과 일치해야 한다.
  - Depends on: SG2

- [x] SG4: 선택 트랙 lazy loader와 baseline/enhanced resource policy 구현
  - Outcome: 현재 선택 트랙 base pack만 필수 로드하고 enhanced에서 supplemental geometry만 더하며, 중복 decode와 트랙 전환 메모리 누적 없이 shared resource를 제공한다.
  - Work: `RacingEnvironmentAssetLibrary.swift`, `RacingEnvironmentQuality.swift`와 `RacingEnvironmentQualityTests.swift`(신규 후보)를 추가하고 `RacingWorldResources`를 연결한다. `project.pbxproj`에 production/test source membership을 추가한다. texture loader는 `.color/.normal/.scalar` semantic과 full mipmap `.allocateAndGenerateAll`을 명시한다. production initial selector는 Low Power Mode off, thermal nominal/fair, physical memory≥8GiB일 때만 enhanced를 허용하고 Simulator·unknown·그 외 기기는 baseline으로 둔다. DEBUG 강제 tier, 한 트랙 bounded cache, concurrent request coalescing, 기존 primitive low-detail fallback과 diagnostic을 구현한다.
  - Verify: 3개 트랙의 baseline/enhanced 강제 load, semantic/full-mipmap option, invalid manifest/asset fallback, 동시 요청 single decode, coastal→alpine→desert 후 active/resident cache≤1 track, app/test source membership, Simulator 기본 baseline과 launch-argument override를 unit/async test로 검증한다. 4/6/8GiB, Low Power Mode, thermal state 입력 table test에서 initial tier 예상값을 고정한다. Simulator에서 asset load 중 HUD·차량·도로와 countdown이 멈추지 않아야 한다.
  - Depends on: SG1, SG3

- [x] SG5: 3단 환경 scene, PBR terrain, contact shadow와 연속 hero vista 통합
  - Outcome: 각 트랙 clear 주행에서 전경·중경·원경이 분명하고, PBR terrain transition과 접지된 자연물이 보이며, hero vista가 tile recycle 경계에서 pop/disappear하지 않는다.
  - Work: `RacingEnvironmentScene.swift`(신규 후보)와 `RacingWorldView.swift`를 연결하고 `project.pbxproj`에 production source membership을 추가한다. `foreground/midground/far/hero/weather` 고정 root, PBR shoulder/terrain, atlas UV transition decal, 근거리 contact-shadow decal, distance haze coefficients와 독립 hero anchor를 구성한다. 기존 광역 단색 ground와 primitive massif/palm/pine/cactus/rock 정상 경로를 제거하되 asset failure fallback은 유지한다.
  - Verify: hierarchy test가 production source membership, 3 layer+hero, near→mid→far 단조 haze, hero framing sample, tunnel/arch bounds와 road clearance, environment의 collision/input component 부재, entity/material budget을 검증한다. 세 트랙 clear를 각각 60초 주행해 정상 asset 경로에서 primitive fallback이 활성화되지 않고 primitive 인상, ground seam, hero pop, floating prop, road obstruction이 없어야 한다.
  - Depends on: SG4

- [x] SG6: 논리 세그먼트 군집, 연속 recycle, LOD와 parallax 적용
  - Outcome: 216m tile pool을 유지하면서 자연물 패턴의 짧은 반복이 사라지고, recycle과 LOD 전환에서 allocation spike·flash·seam이 보이지 않는다.
  - Work: `RacingEnvironmentLayout.swift`, `RacingEnvironmentScene.swift`, `RacingWorldView.swift` update를 연결한다. preallocated prop slot에 logical segment 기반 variant/scale/yaw/tint/cluster plan을 적용하고, 인접 동일 variant 회피, shared mesh/material, near LOD hysteresis와 mid/far double-band parallax를 구현한다. update 중 Entity 생성·삭제와 매-frame material 재생성을 금지한다.
  - Verify: 256 segment 표본의 variant coverage와 short-cycle tuple 비반복, seed 재현성, recycle당 entity/allocation count 불변, LOD hysteresis, quality별 density budget, 기존 18타일 spacing/overlap을 자동 검증한다. 각 트랙을 2분 주행해 좌우 동시 반복, recycle seam, LOD flash, 떠 있는 자연물과 corridor 침범이 없어야 한다.
  - Depends on: SG1, SG5

- [x] SG7: 날씨-자연물 결합과 접근성 안전성 구현
  - Outcome: 3×4 트랙/날씨 조합에서 rain의 젖은 terrain/rock·puddle, fog의 깊이별 소실, storm의 bounded dust/spray·식생 sway가 보이면서 차량·도로·장애물 판독성이 유지된다.
  - Work: `RacingEnvironmentWeather.swift`, `RacingEnvironmentWeatherTests.swift`(신규 후보), `RacingEnvironmentScene.swift`와 기존 `RacingWeatherOverlay`를 하나의 finite `WeatherPresentationState`로 연결하고 `project.pbxproj`에 production/test source membership을 추가한다. `SensoryAccessibilityPolicy`의 Reduce Motion/Reduce Transparency를 전달해 Reduce Motion에서는 vegetation sway, moving world haze와 dust/spray translation을 끄고 lightning을 translation/scale 없는 reduced static opacity cue로 clamp한다. Reduce Transparency에서는 translucent overlay를 줄이되 world depth cue와 정보 판독성을 유지한다. 한 주행 material set을 사전 생성하고 wetness/roughness/clearcoat, layer visibility, puddle enable과 bounded effect state만 갱신한다.
  - Verify: clear/rain/fog/storm의 material·visibility·particle·sway contract, `rain/storm wetness > clear`, fog `near visibility > mid > far`, storm phase 결정론, bounded particle count, update 전후 entity/material 수 불변, app/test source membership과 accessibility clamp를 테스트한다. Reduce Motion×Reduce Transparency 네 조합을 unit test와 12조합 visual smoke에 포함하고 HUD/차량/장애물 대비를 관찰한다.
  - Depends on: SG5, SG6

- [x] SG8: adaptive quality downgrade, 전체 회귀와 Simulator acceptance 완료
  - Outcome: baseline/enhanced가 같은 composition을 유지하면서 density·LOD·shadow·weather detail만 다르고, thermal/memory/지속 저프레임 시 baseline으로 한 번만 downgrade하며 전체 앱 회귀와 예산 gate를 통과한다.
  - Work: `RacingEnvironmentQuality.swift`, scene/resource policy와 acceptance instrumentation을 완성한다. `Scripts/run_racing_environment_acceptance.sh`(신규 후보)를 만들어 3트랙×4날씨, forced tier, FPS/memory/route-cycle, active environment cache count와 안정된 game-route `MTLDevice.currentAllocatedSize` evidence를 `.woohyuk/racing-environment-acceptance/`에 수집한다. racing 진입 5초 warm-up 뒤 1초 평균 FPS를 표본화하고 50FPS 미만이 3회 연속이면 downgrade한다. thermal serious/critical과 memory warning은 즉시 downgrade한다. 모든 downgrade는 run-scoped one-way이며 다음 주행 전 자동 재승격하지 않는다. physical-device release checklist를 README 또는 완료 기록에 남긴다.
  - Verify: selector/downgrade unit test가 5초 warm-up, 1초 sample, `<50` 3회 연속, 중간 회복 reset, thermal/memory 즉시 전환, run-scoped one-way/no-reupgrade를 검증하고 acceptance log가 reason·sample count·tier transition을 assertion한다. 전체 iOS/watchOS tests와 Debug/Release build, baseline 3트랙 clear/storm FPS matrix, Reduce Motion×Transparency를 포함한 전체 12조합 visual smoke, 최악 조합 300초 soak, 세 트랙 순환 10회 route release/RSS, bundle decoded-equivalent와 route resident gate를 실행한다. game-route total Metal resident≤64MiB, 전환 전후 active/resident environment cache≤1 track이어야 한다. Simulator gate는 평균 58FPS 이상, 연속 2회 50FPS 미만 없음, freeze/state loss 없음, final RSS≤baseline 115%, last-five strict growth 없음, controller/scene 10/10 release다. forced enhanced는 hierarchy/density와 무충돌을 검증하되 성능 승인은 실제 최신 iPhone follow-up으로 남긴다.
  - Depends on: SG1–SG7

## Final Verification

- `git diff --check`와 exact file/status inspection을 실행하고 `shasum -a 256 docs/screenshots/weather-{clear,rain,fog,storm}.jpg` 결과를 Current Evidence의 네 SHA와 비교한다. 네 파일이 계속 추적 상태이고 `git diff -- docs/screenshots/weather-{clear,rain,fog,storm}.jpg`가 비어 있음을 확인해 내용·상태 보존을 증명한다.
- 환경 USD/PBR generator를 서로 다른 임시 디렉터리에 두 번 실행하고 derived SHA 목록이 동일한지 비교한다. 모든 USDA는 `/usr/bin/usdchecker`, 모든 USDZ는 `/usr/bin/usdzip --checkCompliance`를 통과해야 한다.
- `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' test`
- `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' test`
- iOS/watchOS Debug와 Release 네 build를 모두 실행한다.
- 확장된 `Scripts/measure_compiled_texture_memory.swift`로 atlas/background/presentation/기존 Racing3D PBR/신규 environment를 family별로 열거하고, environment=36MiB·bundle decoded-equivalent≤112MiB·단일 dimension≤2048을 확인한다. environment manifest/provenance/SHA/bundle membership test도 통과시킨다.
- acceptance instrumentation에서 full mipmap이 유지되는지, game-route total Metal resident≤64MiB와 active/resident environment cache≤1 track인지 확인한다. 12MiB는 manifest/decoded base-level 정적 계약으로만 검증하고 Metal delta와 비교하지 않는다.
- `Scripts/run_racing_environment_acceptance.sh`로 12개 track/weather visual smoke, baseline/enhanced forced tier, baseline clear/storm FPS matrix, 최악 조합 300초 soak와 10-cycle memory/release를 수집한다.
- 수동 Simulator 검증: 각 트랙 clear 60초와 2분 반복 주행에서 3단 원근, hero 연속성, terrain seam, contact shadow, variant 반복, recycle/LOD pop을 확인한다. 12조합에서 wetness/puddle/depth fog/storm sway·dust와 차량·장애물 판독성을 확인한다.
- 비차단 physical-device follow-up: iPhone 13 Release baseline 15분, 최신 iPhone enhanced 15분, Metal/thermal/memory trace와 paired Watch steering smoke. 이 검증 전에는 App Store release-ready 성능을 주장하지 않는다.

## Progress

2026-08-30: Ralph를 시작했다. preflight에서 active plan을 읽고 `main == origin/main == 47ebb7c`를 확인했으며, 직전 날씨 스크린샷 커밋으로 stale해진 Git/status evidence와 보존 계약을 구현 전에 갱신했다.

2026-08-30: SG1 완료. 트랙별 안정 seed/catalog, 3단 layer·hero·clearance·quality budget, SplitMix64 결정론 cluster plan과 `TrackTileState(distance, logicalSegmentIndex)`를 추가했다. 기존 12m×18 tile distance wrapper를 보존했고 extreme finite travel overflow를 2차 시도에서 보정했다. 독립 tester가 focused XCTest 32개(기존 22+신규 10), `git diff --check`, PBX lint와 travel 경계 matrix를 PASS했다.

2026-08-30: SG2 완료. built-in image generation으로 Ocean/Alpine/Desert source master 3장을 생성해 source ID·prompt·SHA와 함께 고정하고, 결정론 USDA/USDZ 및 CoreGraphics PBR atlas pipeline, manifest schema, provenance와 five-way negative validation을 추가했다. 독립 tester가 서로 다른 임시 경로의 21개 산출물 SHA 일치, 6 USDA+6 USDZ compliance, 9 PNG sRGB/linear-sRGB·RGBA·roughness channel 계약, source/protected screenshot hash 보존을 PASS했다.

2026-08-31: SG3 완료. 6 USDA·6 deterministic USDZ·9 PBR PNG를 생성하고 manifest/provenance의 21개 derived SHA를 verified로 확정했다. iOS bundle에는 manifest+6 USDZ+9 PNG만 등록하고 USDA/source/Watch membership을 제외했다. 독립 tester가 focused asset XCTest 7/7, fresh regeneration 21/21 byte identity, USDA/USDZ 12/12 compliance, built-app family 측정 environment 36MiB·total 101.11MiB≤112MiB·max 2048을 PASS했다.

2026-08-31: SG4 완료. pure initial quality selector, selected-track base/enhanced loader, full-mipmap semantic texture load, fallback diagnostic, same-request coalescing과 one-track bounded cache를 추가했다. 기존 world를 먼저 add한 뒤 authored resources를 비동기로 component에 연결해 SG5 경계를 만들었다. 독립 tester가 quality+asset XCTest 16/16, fresh Debug build, 12 concurrent request→decode 1회, baseline→enhanced base/texture 재사용, 3-track cache≤1을 PASS했다.

2026-08-31: SG5 완료. foreground/midground/far/hero/weather/terrain/decal/contact-shadow 직접 root, 세 트랙 baseline/enhanced authored assembly, 연속 PBR terrain·4-quadrant transition decal·contact shadow와 독립 hero anchor를 통합했다. 실패 시 legacy scene을 유지하고 성공 후에만 기존 광역 환경을 비활성화하며 update 중 entity/material 수를 고정했다. 독립 tester가 Scene+Quality+Asset XCTest 22/22와 fresh Debug build를 PASS했고, iPhone 17 Pro Max Simulator에서 forced baseline Ocean Drive Clear를 touch 주행으로 진입해 정상 렌더링과 56–58 FPS를 확인했다. Alpine/Desert 60초 수동 주행은 SG6 이후 acceptance로 이월했다.

2026-08-31: SG6 완료. logical segment+track seed+role/slot salt 기반 variant plan, 인접 primary 회피, 18-segment preallocated prop/render/contact-shadow pool, 38m/50m near LOD hysteresis와 mid/far 2-band parallax를 Scene update에 연결했다. recycle 중 transform·enable·opacity·기존 component만 갱신하고 entity/mesh/material 생성·삭제·reparent를 금지했다. 독립 tester가 WorldLayout+Layout+Scene+Quality+Asset XCTest 61/61, fresh Debug build, 256-segment 다양성, recycle 경계 identity/count 불변과 해시 보존을 PASS했다. 최신 forced baseline Ocean Drive Clear Simulator smoke에서도 56–58 FPS와 연속 도로/환경 렌더링을 확인했으며, 세 트랙 각 2분 수동 주행은 SG8 acceptance로 이월했다.

2026-08-31: SG7 완료. 한 번 계산한 finite WeatherPresentationState를 RealityKit scene과 SwiftUI overlay에 공유하고, clear/rain/fog/storm의 wetness·roughness·puddle·depth visibility·deterministic storm phase를 세 트랙과 두 tier에 연결했다. dry/wet material set과 rain/dust-spray/haze/puddle/lightning 6개 effect batch를 조립 시 사전 생성해 logical particle capacity 80/140을 지키면서 update identity/count를 고정했다. Reduce Motion은 sway와 moving haze/rain/dust-spray를 정지시키고 static lightning cue를 사용하며, Reduce Transparency는 overlay만 낮추고 world depth cue를 유지한다. 독립 tester가 Weather 포함 6개 suite 70/70, fresh Debug build, 12상태·4접근성 조합·무할당 update·SG5/SG6 회귀와 보존 해시를 PASS했다. 12조합 visual smoke는 SG8 acceptance로 이월했다.

2026-08-31: SG8 자동화·성능 계약은 구현되었고 full acceptance evidence `20260830T214730Z`가 28/28 시나리오를 기록했다. 다만 계획 전체 독립 tester가 15개 visual 캡처가 주행 장면이 아닌 `GET READY 3` countdown overlay에 고정되어 있음을 재현해 visual acceptance를 fail-open으로 판정했다. screenshot capture를 racing readiness에 동기화하고 12조합+3 enhanced 캡처를 재수집할 때까지 SG8을 재개한다. 실제 iPhone/Apple Watch Release 검증은 `docs/racing-environment-physical-device-follow-up.md`에 pending/nonblocking으로 남긴다.

2026-08-31: SG8 최종 완료. SwiftUI `.racing` rendered probe와 첫 유효 1초 FPS sample 이후 PID-scoped readiness token을 1회 발행하고, runner가 `route=playing`, `phase=racing`, `rendered=true`, `countdownOverlay=false`를 확인한 뒤에만 캡처하도록 fail-closed 동기화했다. 새 full evidence `20260830T224924Z`는 28/28 시나리오와 실제 주행 캡처 15/15를 PASS했다. 6개 FPS matrix 평균 58.703–59.451FPS, 300초 soak 평균 59.248FPS·최저 51·streak 0, route controller/scene 10/10 release, adaptive memory warning과 접근성 4조합을 모두 통과했다. 독립 tester가 현재 소스 focused XCTest 30/30, 15개 PID/token/summary와 전수 캡처, exact framework retry 1건, texture 101.11MiB/environment 36MiB, 보호·source hash를 재검증해 PASS했다. 실물 검증은 pending/nonblocking이다.

## Risks

- 생성 원본은 비결정적일 수 있다. 선택 source master와 SHA를 저장소에 고정하고 processor가 source mismatch를 거부하게 하며 derived asset만 결정론적으로 재생성한다.
- generated texture의 seam, color-space와 height-derived normal artifact가 생길 수 있다. wrapped edge blend, fixed crop/atlas, `.color` sRGB와 `.normal/.scalar` linear data-map semantic, mipmap과 channel contract를 자동 검사한다.
- authored variant가 많아도 pool index 기반이면 반복된다. Swift `hashValue` 대신 logical segment+track seed+role salt+slot index fixed RNG를 사용하고 인접 동일 variant를 피한다.
- tile recycle 시 clone/add/remove는 12m마다 hitch를 만들 수 있다. Entity slot을 미리 만들고 shared component, enable state와 transform만 교체한다.
- LOD pop과 hero disappearance가 시야 중심에서 드러날 수 있다. threshold hysteresis와 haze-hidden transition을 사용하고 hero는 독립 anchor와 장거리 silhouette을 유지한다.
- 세 트랙 texture와 geometry를 모두 cache하면 RSS가 누적될 수 있다. 현재/최근 한 트랙 bounded cache와 enhanced supplemental geometry를 사용하고 route-cycle release를 gate로 둔다.
- draw call과 shadow가 급증할 수 있다. variant mesh를 1–2 material slot으로 flatten하고 baseline shadow/contact decal을 near/hero에 집중하며 mid/far는 baked tonal separation을 사용한다.
- weather material을 매 frame 생성하면 churn이 발생한다. finite material set을 주행 시작 시 만들고 opacity/transform/enable/emission만 변경한다.
- SwiftUI fog와 world haze가 중복되면 화면이 씻기고 장애물이 안 보일 수 있다. 하나의 weather state가 두 경로의 총량을 분배하고 12조합 판독성을 gate로 둔다.
- adaptive tier가 흔들릴 수 있다. downgrade hysteresis와 run-scoped one-way 전환을 사용하고 재승격은 다음 주행에서만 허용한다.
- Simulator 성능은 iPhone 13을 증명하지 못한다. Simulator 수치는 회귀 gate로만 사용하고 physical-device Release 검증을 출시 전 필수로 남긴다.

## Open Questions

- None

## Implementation Result

Implemented on 2026-08-31.

### Summary

- Ocean Drive, Alpine Pass, Desert Circuit에 authored base/enhanced USDZ와 트랙별 PBR terrain atlas를 추가하고, 전경·중경·원경·hero가 이어지는 프리미엄 스타일라이즈드 환경으로 교체했다.
- 논리 세그먼트와 fixed RNG, preallocated prop pool, LOD hysteresis, parallax와 bounded one-track cache로 반복·seam·런타임 allocation을 제어했다.
- clear/rain/fog/storm의 wetness, puddle, depth haze, sway, dust/spray와 Reduce Motion·Reduce Transparency 정책을 하나의 finite presentation state로 통합했다.
- 5초 warm-up과 1초 FPS sampling을 사용하는 run-scoped adaptive quality downgrade, thermal/memory 즉시 전환과 in-place tier update를 구현했다.
- PID-scoped racing readiness 뒤에만 캡처하는 fail-closed acceptance runner를 추가해 countdown 화면을 visual evidence로 오인하지 않도록 했다.

### Completed Subgoals

- [x] SG1: 결정론적 환경 catalog, 논리 세그먼트와 layout 계약을 검증했다.
- [x] SG2: 재현 가능한 USDZ/PBR authoring pipeline, manifest와 provenance를 구축했다.
- [x] SG3: 세 트랙의 base/enhanced 자연 pack과 36MiB PBR atlas를 번들에 통합했다.
- [x] SG4: semantic/full-mipmap lazy loader, coalescing과 one-track cache를 검증했다.
- [x] SG5: 3단 scene, PBR terrain, contact shadow와 연속 hero vista를 통합했다.
- [x] SG6: preallocated recycle, 결정론 군집, LOD hysteresis와 parallax를 적용했다.
- [x] SG7: 네 날씨와 두 접근성 정책의 자연 환경 반응을 구현했다.
- [x] SG8: adaptive downgrade와 전체 Simulator acceptance를 완료했다.

### Changed Files

- `WatchCarRacer/iOS/Game/RacingEnvironment*.swift`: catalog, layout, asset loading, quality, scene과 weather runtime을 추가했다.
- `WatchCarRacer/iOS/Game/RacingWorldView.swift`, `GameLoopDriver.swift`, `GameScene.swift`: authored environment lifecycle, fixed 60Hz cadence와 production frame sampling을 연결했다.
- `WatchCarRacer/iOS/App/GameRootView.swift`, `GameSessionController.swift`, `SG6AcceptanceCoordinator.swift`, `WatchCarRacerApp.swift`: tier 전달, thermal/memory lifecycle, sensory feedback와 acceptance instrumentation을 연결했다.
- `WatchCarRacer/iOS/Resources/RacingEnvironment3D/`: manifest, 6 USDA, 6 USDZ와 9 PBR PNG를 추가했다. USDA는 authoring source이며 app bundle에서 제외된다.
- `Scripts/build_racing_environment_usd.swift`, `build_racing_environment_pbr_maps.swift`, `measure_compiled_texture_memory.swift`: 결정론적 생성·검증과 texture budget 측정을 구현했다.
- `Scripts/run_sg6_acceptance.sh`, `run_racing_environment_acceptance.sh`: PID-scoped readiness, fail-closed visual/performance/soak/route/adaptive/accessibility acceptance를 구현했다.
- `WatchCarRacerTests/RacingEnvironment*Tests.swift`, `GameAssetLibraryTests.swift`, `SG8SensoryAcceptanceTests.swift`: layout·asset·quality·scene·weather·sensory 회귀를 추가했다.
- `WatchCarRacer.xcodeproj/project.pbxproj`, `docs/assets/provenance.md`, `docs/assets/sources/racing-environment/`, `docs/racing-environment-physical-device-follow-up.md`: target membership, source provenance와 실물 검증 checklist를 기록했다.

### Verification

- 최종 독립 tester: PASS.
- 서로 다른 임시 디렉터리의 asset 생성 2회: 21/21 byte-identical; USDA/USDZ 12/12 compliance PASS.
- 전체 iOS XCTest: 272/272 PASS; watchOS XCTest: 13/13 PASS.
- 현재 focused iOS XCTest: 46/46 PASS.
- iOS/watchOS Debug·Release 4개 build: PASS.
- `Scripts/measure_compiled_texture_memory.swift`: total 101.11MiB≤112MiB, environment 36MiB, max dimension 2048 PASS.
- 최종 acceptance `.woohyuk/racing-environment-acceptance/20260830T224924Z`: 28/28 scenarios, 실제 주행 screenshots 15/15 PASS.
- 6개 FPS matrix 평균 58.703–59.451FPS, 300초 soak 평균 59.248FPS·최저 51·freeze/state loss 없음, route controller/scene 10/10 release·RSS 1.0421× PASS.
- 보호 weather 4종과 generated source master 3종 SHA, PBX/manifest/shell syntax, executable bit와 `git diff --check`: PASS.
- 최종 standalone watchOS test 재시도 1회는 disconnected Simulator pair의 `IOSSHLMainWorkspace` 오류로 product test 실행 전에 중단됐지만, 앞선 13/13 watchOS test와 현재 watchOS Debug/Release build evidence는 PASS다.

### Follow-ups

- App Store 성능 승인을 주장하기 전에 `docs/racing-environment-physical-device-follow-up.md`의 iPhone 13 baseline, 최신 iPhone enhanced, Metal/thermal/memory trace와 paired Apple Watch steering 검증을 수행한다. 현재는 사용자 요청에 따라 pending/nonblocking이다.
