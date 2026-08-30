---
title: "시네마틱 주행 사운드와 감각 연출 고도화"
status: implemented
created: 2026-08-29
updated: 2026-08-30
implemented_at: 2026-08-30
target_repo: "/Users/woohyuk/Desktop/watch-car-racer"
goal_size: large
feature_slug: "cinematic-sensory-polish"
---

# 시네마틱 주행 사운드와 감각 연출 고도화

## Goal

현재의 프리미엄 허브·차량 정비 UX에 속도 연동 엔진/도로/바람 사운드, 시네마틱 충돌, 속도감 표현, 3·2·1·GO 출발 의식, 방향성 near-miss와 route micro-interaction을 통합한다. 모든 감각 피드백은 기존 결정론적 시뮬레이션과 Watch/touch 조향 결과를 바꾸지 않으며, 사용자 설정과 시스템 접근성 선호를 일관되게 따른다.

## Assumptions

- 오디오 원본은 프로젝트를 위해 직접 제작했거나 재배포가 명확히 허용된 source만 사용한다. CC0·royalty-free source를 사용할 경우 작성자, 원문 URL, license/version, 취득일, 변환 내역과 shipped SHA-256을 기록한다.
- 실물 iPhone/Apple Watch를 현재 사용할 수 없다. Simulator·unit/runtime acceptance는 차단 조건이며 실제 스피커/헤드폰 음량, 좌우 공간감, Watch 햅틱 강도·지연, 장시간 배터리/열은 비차단 physical-device follow-up이다.
- iPhone/Watch의 출발 햅틱 동기화는 같은 logical cue에서 iPhone 햅틱과 reachable Watch packet을 함께 fan-out하는 best-effort 의미다. `WatchConnectivity`는 sample-accurate 동기를 보장하지 않는다.
- 현재 환경인 Xcode 26.4, iPhone 17 Pro Max iOS 26.4, iPhone SE (3rd generation) iOS 26.0, Apple Watch Series 11 (46mm) watchOS 26.4를 계속 사용한다.
- `main`의 기준 commit은 원격에 push된 `d07e593`이다. `WatchCarRacerWatchApp.xcscheme`에는 Xcode가 만든 unstaged formatting-only 사용자 변경이 있으므로 계획 전체에서 보존하고 수정·정리·커밋하지 않는다. 계획 시작 시 file SHA-256은 `d84cce7bea7e7bf7b31cd7a92a0569bd293aa98829e69e77f2a3bad227884f6a`, `git diff --binary` patch SHA-256은 `a7095007ccebc3c93b541413abdbc88f56b52bdaacfe0fcb66869bd713d78d35`다.

## Decisions

- 사용자 결정 1-A: 오디오는 project-original 또는 license가 명확한 source asset과 runtime pitch/crossfade/mix를 결합한 hybrid 방식으로 구현한다.
- 사용자 결정 2-A: 효과 강도는 장애물 판독성과 조작 응답을 보존하는 cinematic arcade balance로 구성한다.
- 사용자 결정 3-A: 이번 범위에 full BGM은 넣지 않는다. 엔진/SFX/환경음과 persistent SFX·haptics·effect-intensity 설정을 제공한다.
- effect intensity는 `Balanced`와 `Reduced` 두 값만 제공하고 기본값은 `Balanced`다. 별도 `High` mode와 channel별 volume slider는 추가하지 않는다.
- first-party `AVFoundation`, SpriteKit, SwiftUI, UIKit, WatchKit만 사용하며 third-party runtime/audio dependency와 background-audio capability는 추가하지 않는다.
- app-lifetime `GameAudioDirector`가 하나의 `AVAudioEngine`과 route/game context를 소유한다. 게임 session은 logical state와 finite parameter만 전달하고 audio가 gameplay로 callback하지 않는다.
- `GameSimulation`, `RoadProjection`, spawn/collision/score/difficulty와 steering packet을 변경하지 않는다. near-miss 방향·closeness·presentation chain은 같은 fixed step의 snapshot에서 별도 presentation context로 계산한다.
- collision 시 immutable `RunResult`는 impact 시점에 한 번 기록한다. `.collision(result)` presentation phase에서 약 520ms의 cancellable choreography를 실행한 뒤 `.result(result)`를 표시한다.
- system Reduce Motion/Reduce Transparency clamp를 사용자 effect intensity 뒤에 적용한다. Reduce Motion은 decorative translation/scale/rotation을 제거하고, Reduce Transparency는 fog/translucent treatment를 억제하며 정보성 flash·edge marker·label은 유지한다.
- SFX를 끄면 audio cue와 ambience만 중지하고 haptic은 설정대로 유지한다. Haptics를 끄면 iPhone generator와 Watch feedback packet을 모두 막고 audio는 설정대로 유지한다.
- packaged audio 누락·manifest 오류는 asset readiness 실패다. audio interruption, route change, media-services reset이나 Watch send 실패는 gameplay를 막지 않고 현재 logical context에서 복구하거나 조용히 degrade한다.
- 사용자 승인(2026-08-29): Xcode 26.4 Instruments가 Simulator process에 `Game Memory` template로 attach/export하지 못하는 현재 환경에서 exportable `xctrace` gate를 면제한다. 대신 동일 임계값을 사용한 반복 runtime memory summary(RSS≤baseline 115%, last-five strict growth 없음, controller/scene 10/10 release) PASS와 xctrace 외부 blocker evidence를 SG8의 memory 완료 조건으로 인정한다. Exportable trace는 non-blocking tooling follow-up으로 남긴다.

## Audio Source Contract

SG2는 외부 입력을 기다리지 않고 project-original source kit를 직접 authoring한다. repository-owned offline Swift tool이 layered oscillator/noise/envelope와 원본 mix recipe를 48kHz 16-bit PCM file로 render하며 runtime 합성은 하지 않는다. 명확한 재배포 license를 가진 source로 교체할 수 있지만 동일 manifest·provenance·quality gate를 통과해야 한다.

| Role | Channels | Duration | Loop |
| --- | ---: | ---: | --- |
| `engine_idle_loop` | 1 | 1.0...4.0s | yes |
| `engine_mid_loop` | 1 | 1.0...4.0s | yes |
| `engine_high_loop` | 1 | 1.0...4.0s | yes |
| `road_loop` | 1 | 1.0...4.0s | yes |
| `wind_loop` | 1 | 1.0...4.0s | yes |
| `tire_scrub_loop` | 1 | 1.0...4.0s | yes |
| `near_miss_whoosh` | 1 | 0.08...1.0s | no |
| `collision_impact` | 1 | 0.10...1.0s | no |
| `countdown_tick` | 1 | 0.05...0.35s | no |
| `go_bass_hit` | 1 | 0.10...0.80s | no |
| `hub_ambience_loop` | 2 | 2.0...8.0s | yes |
| `maintenance_ambience_loop` | 2 | 2.0...8.0s | yes |
| `vehicle_select` | 1 | 0.03...0.50s | no |
| `color_select` | 1 | 0.03...0.50s | no |
| `drive_transition` | 1 | 0.10...0.80s | no |

모든 file은 normalized peak `0.05...0.98`, absolute DC offset `≤0.01`이어야 한다. loop role은 처음/마지막 10ms window의 normalized mean-absolute difference `≤0.08`, RMS difference `≤0.05`를 만족해야 한다. 전체 decoded PCM은 8MiB 이하다.

## Start Cue Contract

| Cue | Audio | Visual | iPhone haptic | Watch feedback | Reduced/Reduce Motion | Visible accent |
| --- | --- | --- | --- | --- | --- | ---: |
| `3` | `countdown_tick`, rate 0.88 | cyan ring/opacity pulse | light impact, intensity 0.35 | `countdownTick`→`.click` | Reduced alpha 55%; Reduce Motion opacity-only | 180ms within 1s step |
| `2` | `countdown_tick`, rate 1.00 | mint ring/opacity pulse | rigid impact, intensity 0.55 | `countdownTick`→`.click` | Reduced alpha 55%; Reduce Motion opacity-only | 180ms within 1s step |
| `1` | `countdown_tick`, rate 1.12 | orange ring/opacity pulse | rigid impact, intensity 0.75 | `countdownTick`→`.click` | Reduced alpha 55%; Reduce Motion opacity-only | 180ms within 1s step |
| `GO` | `go_bass_hit`, rate 1.00 | mint-white full-screen sweep + `GO` | heavy impact, intensity 0.90 | `go`→`.start` | Reduced alpha 55%; Reduce Motion static opacity flash | 260ms while racing begins |

`GO`는 countdown total 3초를 늘리지 않는다. 3→2→1의 각 logical phase는 1초이고 GO cue emission 직후 simulation을 한 번만 unpause하며, GO overlay만 racing 위에 260ms 유지된다.

## Lifecycle Contract

| Presentation phase at transition | inactive/background action | active re-entry | Audio behavior |
| --- | --- | --- | --- |
| countdown | countdown task cancel, scene pause, attempt state 보존 | 같은 attempt를 새 `3`부터 시작 | 즉시 fade/suspend, 새 countdown context 재개 |
| racing | scene pause, touch reset, score/distance/seed 보존 | 같은 attempt를 새 `3`부터 시작 | 즉시 fade/suspend, countdown context로 재개 |
| collision | collision task cancel, immutable result 유지, `.result`로 승격, scene pause | result에 머물고 impact를 replay하지 않음 | impact/engine stop, result context만 재개 |
| result | scene pause, result 유지 | result에 머물고 racing으로 복귀하지 않음 | suspend 후 result context만 재개 |

Audio interruption begin/end는 presentation phase를 바꾸지 않는다. begin은 audio만 suspend/deactivate하고, resumable end·route change·media-services reset은 현재 desired context만 rebuild/restart한다.

## Scope

- versioned sensory settings store/controller와 hub의 compact settings surface.
- iOS-only audio source kit, `AudioAssetManifest.json`, provenance/SHA와 format/loop/buffer 검사.
- app-lifetime `AVAudioEngine` director, idle/mid/high engine crossfade, road/wind/tire scrub loop, bounded one-shot pool과 lifecycle/interruption 복구.
- near-miss/collision same-step side·closeness context, presentation-only grade/chain, haptic rate limiting과 Watch cue 확장.
- 차량 body roll/shadow, deterministic pooled streak/light/fog, centered camera expression과 방향성 edge feedback.
- distinct 3·2·1 tick, GO bass/light sweep와 iPhone/Watch haptic fan-out.
- 520ms collision hit-stop/camera/debris/recoil choreography와 delayed result.
- hub/maintenance ambience, vehicle/color selection SFX, hero material sweep와 successful Drive transition.
- simulator unit/integration/visual/AX, full build matrix, FPS/memory/presentation/audio-budget acceptance.

## Out Of Scope

- full/adaptive BGM, licensed commercial music, beat synchronization, music ducking과 music settings.
- `High`/extreme effect mode, per-channel volume sliders, equalizer, audio device picker와 custom spatial-audio setup.
- new score multiplier, combo bonus, currency, progression, vehicle performance, difficulty, spawn 또는 collision rule.
- `GameSimulation`, `RoadProjection`, `VehicleCatalog`, Watch steering packet/version, freshness/router/calibration 규칙 변경.
- Metal renderer, `SKEffectNode` blur/post-process, 새 PNG texture, third-party audio engine와 background playback.
- sample-accurate iPhone↔Watch 햅틱 synchronization.
- 실제 iPhone/Watch 스피커·헤드폰·햅틱·열·배터리 tuning을 simulator completion의 차단 조건으로 삼는 일.

## Current Evidence

- Git: `main`/`origin/main`은 `d07e593`이며 premium hub/maintenance/countdown/result 구현이 push되어 있다. Watch scheme의 formatting-only unstaged 변경 한 건은 이번 계획 밖 사용자 변경이다.
- `WatchCarRacer/iOS/Feedback/PhoneFeedbackPlayer.swift`: 22.05kHz mono procedural near-miss 0.14초, collision 0.24초 cue와 iPhone haptic만 있으며 continuous engine, pan, route ambience, settings와 interruption recovery가 없다.
- `WatchCarRacer/iOS/App/GameSessionController.swift`: countdown, route/input, feedback dedupe/fan-out, lifecycle와 result recording을 소유하며 collision callback에서 곧바로 `.result`로 전환한다.
- `WatchCarRacer/iOS/Game/GameScene.swift`: fixed 60Hz simulation/render, near-miss camera punch·mint flash·score pop, collision shake·red flash·18 particles를 제공한다. crashed simulation은 inert라 presentation delay가 score/distance/spawn을 바꾸지 않는다.
- `WatchCarRacer/iOS/Game/GameSimulation.swift`: 같은 step snapshot에 player/obstacle x, dimensions, speed, elapsed time이 있어 raw `GameEvent`를 바꾸지 않고 side/closeness를 계산할 수 있다.
- `WatchCarRacer/iOS/Game/VehicleSpriteNode.swift`: shadow, paint와 details layer가 분리되어 body roll/shadow response seam이 있다.
- `WatchCarRacer/Shared/ControllerMessages.swift`, `WatchCarRacer/Watch/Feedback/WatchHapticPlayer.swift`: feedback kind는 near-miss/collision뿐이며 steering packet과 별도 packet model을 사용한다.
- `WatchCarRacer/iOS/App/MainHubView.swift`, `VehicleMaintenanceView.swift`, `VehiclePresentationView.swift`: route-lazy premium art, landscape scroll fallback과 alpha hero composition을 보유하고 material sweep을 새 texture 없이 올릴 수 있다.
- `WatchCarRacer/iOS/App/GameRootView.swift`: countdown/result overlay와 Reduce Motion propagation을 이미 소유한다.
- `WatchCarRacer/iOS/Resources/`: packaged audio source/manifest는 아직 없다. Xcode resource membership은 `project.pbxproj`에서 수동 관리한다.
- 기존 완료 baseline: iOS 126/126, watchOS 11/11, Debug·Release 네 build, 300 one-second FPS sample 평균/최저 60, 10-cycle memory/release PASS, texture 57.11MiB/max 2048.

## Subgoals

- [x] SG1: persistent sensory settings와 접근성 policy 구현
  - Outcome: 사용자는 hub에서 SFX, iPhone/Watch haptics와 Balanced/Reduced effect intensity를 변경할 수 있고, 값은 relaunch 뒤 복원되며 system Reduce Motion/Transparency가 decorative output을 안전하게 clamp한다.
  - Work: `WatchCarRacer/iOS/Sensory/`에 versioned `SensorySettings`, injectable `UserDefaults` store, app-owned observable controller와 pure `SensoryAccessibilityPolicy`를 추가한다. `WatchCarRacerApp.swift`에서 controller를 생성·주입하고 `MainHubView.swift` action rail에 compact settings disclosure/sheet를 연결한다. default는 SFX on, haptics on, Balanced이며 corrupt/unknown payload는 self-heal한다. project/test target membership을 갱신한다.
  - Verify:
    - `SensorySettingsTests`에서 empty defaults, persistence, corrupt/unknown version self-heal, SFX/haptics 독립 toggle과 Balanced/Reduced round-trip을 검사한다.
    - policy table test에서 user intensity × Reduce Motion × Reduce Transparency 전 조합의 camera/body/streak/debris/fog/panel/static feedback 결과를 검사한다.
    - `GameSimulation.Configuration`과 sensory settings 사이 production dependency가 없고 settings mutation이 route/session/score를 바꾸지 않는지 source/unit audit한다.
    - hub normal/AX Dynamic Type 양쪽 landscape에서 settings control이 44pt target, label/value/hint를 갖고 primary Drive를 가리지 않는지 확인한다.
  - Depends on: None

- [x] SG2: project-original audio source kit와 manifest/provenance 완성
  - Outcome: Ralph가 외부 asset 전달을 기다리지 않고 15개 required role의 production PCM source를 재현 가능하게 제작하며, 모든 file이 명확한 authoring recipe·format·quality·license/SHA 계약을 가진다.
  - Work: `Scripts/build_original_audio_assets.swift`를 repository-owned offline authoring tool로 추가해 layered oscillator/noise/envelope와 original mix recipe로 `WatchCarRacer/iOS/Resources/Audio/`의 48kHz 16-bit PCM source를 render한다. `AudioAssetManifest.json`에 Audio Source Contract의 role/channel/duration/loop와 stable filename을 기록하고 `docs/assets/provenance.md`에 project-original method, tool/version, creation date, transformations와 shipped SHA-256을 추가한다. 명확히 licensed source를 선택해도 동일 manifest와 provenance를 작성하며 third-party runtime/tool dependency는 두지 않는다. `project.pbxproj`의 iOS resource phase에만 등록한다.
  - Verify:
    - authoring tool을 빈 temporary output에 두 번 실행해 role list, byte-for-byte SHA와 manifest metadata가 동일한지 검사한다.
    - `AudioAssetContractTests`에서 15 role exactly-once, file 존재·nonzero PCM decode, 48kHz/16-bit/channel/duration/loop 일치와 normalized peak `0.05...0.98`, absolute DC `≤0.01`을 검사한다.
    - loop role의 first/last 10ms mean-absolute difference `≤0.08`, RMS difference `≤0.05`, 전체 decoded PCM `≤8MiB`를 검사한다.
    - manifest와 provenance의 SHA가 실제 shipped file과 전부 일치하고 license/source field가 비어 있지 않은지 검사한다.
    - Debug/Release iOS bundle은 audio 15개+manifest를 포함하고 Watch app bundle은 audio/manifest 0개인지 검사한다.
  - Depends on: None

- [x] SG3: app-lifetime dynamic audio engine와 lifecycle 구현
  - Outcome: SG2 source가 하나의 app-owned engine에서 hub·maintenance·countdown·racing·impact·result context로 끊김 없이 전환되고 speed/steering에 따라 finite mix가 변하며 Retry/route/background에서도 중복·누수 없이 복구된다.
  - Work: `WatchCarRacer/iOS/Sensory/`에 `AudioAssetLibrary`, pure `AudioMixModel`과 app-owned `GameAudioDirector`를 추가한다. 세 engine layer varispeed/crossfade, road/wind monotonic gain, steering dead-zone tire scrub, ±0.75 equal-power pan one-shot, 최대 30Hz smoothing, long-lived node≤16과 simultaneous one-shot≤4 bounded pool을 구성한다. `WatchCarRacerApp.swift`가 director를 한 번 소유하고 `AppFlowController` asset readiness에 packaged audio validation을 합친다. `.ambient/.mixWithOthers`를 유지하며 Lifecycle Contract와 audio interruption/route/media reset을 구현한다. 기존 runtime procedural cue는 production path에서 제거한다.
  - Verify:
    - `AudioMixModelTests`에서 initial/max speed 경계, engine crossfade gain 합, gain/rate/pan finite clamp, road/wind monotonicity, tire dead zone과 smoothing을 table-test한다.
    - `GameAudioDirectorTests`에서 hub→maintenance→countdown→racing→impact→result, retry, inactive/background, interruption begin/end, route change와 media-services reset 뒤 desired context만 재개되고 app-owned identity가 유지되는지 검사한다.
    - director spy로 60Hz snapshot 입력이 최대 30Hz parameter update가 되고 render/update path에서 node/buffer/file allocation·decode가 0인지 검사한다.
    - SFX off에서 loop/one-shot output 0, SFX on에서 logical cue exactly-once이고 director failure가 score·phase·steering·Watch fallback을 바꾸지 않는지 검사한다.
    - asset manifest 누락/불일치는 readiness failure지만 runtime audio route/interruption 실패는 drive/session 생성과 simulation을 막지 않는지 검사한다.
  - Depends on: SG1, SG2

- [x] SG4: same-step directional feedback와 Watch cue 계약 확장
  - Outcome: near miss와 collision은 실제 obstacle side/closeness에 맞는 presentation grade를 만들고, 3·2·1·GO와 강한 near miss가 설정을 지키며 iPhone/Watch로 한 번만 fan-out된다. score와 raw simulation event는 변하지 않는다.
  - Work: `GameScene.update`의 최대 5회 catch-up loop 안에서 각 `simulation.step` 직후 `stepSnapshot = simulation.snapshot`을 캡처하고, 해당 substep의 raw event와 snapshot/configuration으로 relativeX, side와 closeness를 계산한 internal presentation event wrapper를 누적해 controller에 전달한다. frame 종료 final snapshot을 event context로 재사용하지 않는다. `GameFeedbackCoordinator`에 two-grade near miss, simulation elapsed-time 기준 3초 presentation chain/tier≤3, injected monotonic-clock 150ms near-miss haptic limiter와 settings gating을 추가한다. `WatchFeedbackKind`에 countdown tick, GO와 strong near miss를 좁게 추가하고 `WatchHapticPlayer` mapping을 확장하되 steering packet/version은 유지한다.
  - Verify:
    - side left/center/right, closeness grade 경계, 3초 chain reset/tier cap, retry/collision reset, 150ms rate limit와 collision/GO bypass를 unit-test한다.
    - 한 render frame에서 2...5 fixed step을 강제하고 첫 substep near miss 뒤 player/obstacle가 이동한 final snapshot을 만든 catch-up test에서 side/closeness가 첫 substep snapshot 기준임을 검사한다.
    - label의 `+100`과 simulation score/event sequence가 chain/grade 전후 동일하고 raw `GameEvent` shape가 변경되지 않았는지 snapshot test한다.
    - SFX off는 audio만 0, haptics off는 UIKit invocation·Watch send가 모두 0, 둘 다 on이면 deduped event당 한 번인지 검사한다.
    - ControllerMessages/Watch receiver round-trip, new cue mapping과 unknown/malformed feedback failure 격리를 검사하고 Watch feedback 실패가 steering/session을 바꾸지 않는지 확인한다.
    - `git diff --exit-code d07e593 -- WatchCarRacer/iOS/Game/GameSimulation.swift WatchCarRacer/iOS/Game/RoadProjection.swift WatchCarRacer/iOS/Customization/VehicleCatalog.swift`를 통과한다.
  - Depends on: SG1; SG2의 cue contract 확정 뒤 SG3와 병렬 구현 가능

- [x] SG5: 속도감과 방향성 near-miss visual layer 강화
  - Outcome: racing은 speed와 steering에 반응하는 body/shadow·streak·light/fog·camera 표현을 제공하고 near miss는 지나간 방향과 grade를 즉시 전달하지만 obstacle 판독성, projection과 60fps를 유지한다.
  - Work: `VehicleSpriteNode.swift`와 `GameScene.swift`에 routed steering 기반 body roll/paint-detail offset, speed 기반 shadow compression/alpha, centered nested camera expression을 추가한다. 기존 texture와 pooled SpriteKit shape만 사용해 deterministic edge streak, road light pool, static/recycled fog band와 directional near-miss edge cue를 구성한다. impact transform과 continuous camera transform을 분리하고 crashed final render 뒤 transform action과 frame render가 충돌하지 않게 한다.
  - Verify:
    - `GameScenePresentationTests`에서 speed/steering 경계별 transform, shadow, left/right edge, grade 차이와 centered camera compensation을 검사한다.
    - 6,000 frame run, 100 near misses와 10 retry 뒤 streak/light/fog/debris node count가 fixed bound를 넘지 않고 reset/stop 뒤 actions/ephemeral nodes가 정리되는지 검사한다.
    - Balanced/Reduced/Reduce Motion/Reduce Transparency/두 system setting 결합에서 policy table대로 transform·opacity·static substitute가 적용되는지 검사한다.
    - 기존 `RoadProjectionTests`, `VehicleSpriteNodeTests`, `GameSceneMapTests`가 수정된 simulation expectation 없이 통과한다.
    - 새 PNG, `SKEffectNode`, blur/filter allocation과 per-frame node/buffer/file decode가 없음을 source/runtime audit한다.
  - Depends on: SG1, SG4

- [x] SG6: 3·2·1·GO ritual과 cancellable collision choreography 통합
  - Outcome: 최초 Drive·Retry·foreground 재진입은 distinct 3·2·1 tick과 GO light/audio/haptic을 정확히 한 번 실행하고, collision은 결과를 즉시 고정한 뒤 520ms cinematic impact를 보여준 다음 result로 전환한다.
  - Work: `GameSessionController.swift` countdown generation에 Start Cue Contract의 3/2/1/GO logical cue emission과 audio rate, visual token, iPhone/Watch haptic command를 결합하되 simulation/input freeze와 총 3초 계약을 유지한다. `GameRootView.swift`는 각 tick 180ms accent를 실제 countdown value와 함께 render하고 GO를 racing 위에 정확히 260ms 표시한다. `RunPresentationPhase.collision(RunResult)`과 별도 collision generation/task를 추가한다. t=0 record+flash/audio/haptic, 0–65ms hit-stop, 65–245ms 방향성 camera translation/약 3.5% zoom, 65–405ms recoil/최대 24 debris, 405–500ms settle, t≈520ms result/pause를 구현한다. Retry/Hub/stop/inactive/background는 stale task를 취소하고 Lifecycle Contract에 따라 collision 중 inactive/background는 immutable result를 `.result`로 승격·pause한다.
  - Verify:
    - fake sleeper/clock으로 cue order가 3,2,1,GO이고 tick 간격과 countdown total이 기존 850...1,150ms/2,850...3,150ms를 유지하며 GO 직후 한 번만 racing/unpause하는지 검사한다.
    - view/presentation test에서 3/2/1 각각 180ms accent와 정해진 audio rate·color·iPhone haptic·Watch feedback, GO 260ms overlay/light sweep가 Start Cue Contract와 일치하고 그 뒤 제거되는지 검사한다.
    - countdown 중 score·distance·obstacle·steering read 불변, SFX/haptics setting별 cue fan-out과 unique/deduped IDs를 검사한다.
    - collision t=0에 result record 1회/input disabled, 480ms 전 result overlay 없음, 480...600ms result 표시, scene pause와 24 이하 debris cleanup을 fake clock으로 검사한다.
    - countdown/racing/collision/result × inactive/background/active table test에서 task cancellation, result promotion, scene pause, audio suspend/recovery와 foreground phase가 Lifecycle Contract와 일치하고 stale task가 audio/visual/unpause/result를 재실행하지 않는지 검사한다.
    - Reduce Motion에서는 camera/body/debris transform 없이 static impact·audio·설정상 haptic·동일 result timing이 유지되는지 검사한다.
  - Depends on: SG3, SG4, SG5

- [x] SG7: hub·maintenance ambience와 성공 기반 micro-interaction 완성
  - Outcome: hub와 Pit Lane은 고유 ambience를 갖고 실제 vehicle/color 변경과 성공한 Drive만 SFX·material/route sweep을 한 번 실행하며, Watch sheet 취소나 no-op은 잘못된 피드백을 내지 않는다.
  - Work: `AppRootView.swift` route/lifecycle을 audio director context에 연결한다. `MainHubView.swift`, `VehicleMaintenanceView.swift`, `VehiclePresentationView.swift`에 settings-aware route ambience, successful vehicle/color change cue와 alpha-mask material sweep을 추가한다. direct Watch-ready Drive와 Continue With Touch의 최종 성공 시에만 Drive SFX/full-screen transition을 실행하고 loading/error/not-ready sheet open/cancel/interactive dismiss는 transition을 만들지 않는다. Reduce Motion은 opacity-only, Reduce Transparency는 existing opaque panel fallback을 유지한다.
  - Verify:
    - flow/view-model test에서 changed selection/color만 cue 1회, same-value/no-op/rejected mutation은 0회인지 검사한다.
    - Watch-ready direct Drive와 Continue With Touch success는 transition/audio 각 1회, not-ready sheet open·Cancel·interactive dismiss·asset/controller failure는 0회인지 검사한다.
    - route hub↔maintenance↔hub↔countdown 전환에서 이전 ambience/one-shot이 겹치지 않고 같은 route 재렌더가 audio node/context를 중복 생성하지 않는지 검사한다.
    - Pro Max/SE 양쪽 landscape, maximum Dynamic Type, Reduced Effects, Reduce Motion, Reduce Transparency에서 material/route sweep과 settings가 hero/primary action/AX focus를 가리지 않는지 capture/AX audit한다.
  - Depends on: SG1, SG3

- [x] SG8: 전체 sensory regression·performance·memory acceptance
  - Outcome: 여섯 감각 개선축이 simulator에서 설정·접근성·lifecycle·Watch/touch·Retry 전체 흐름을 회귀시키지 않고 기존 startup/FPS/memory/texture 기준과 새 audio/collision 기준을 만족한다.
  - Work: `SG6AcceptanceCoordinator.swift`와 `Scripts/run_sg6_acceptance.sh`에 sensory mode/summary를 추가해 logical audio context, director identity, cue order/count, settings gating, collision latency, visual pool bound와 cleanup을 자동 수집한다. audio 실제 음질·햅틱 세기는 물리 follow-up과 분리하고, 발견된 결함만 소유 SG 모듈에서 수정한다.
  - Verify:
    - iOS/watchOS full test와 iOS/watchOS Debug·Release 네 build를 Xcode 26.4 지정 simulator에서 실행하고 Swift/Clang warning 0을 확인한다.
    - `Scripts/run_sg6_acceptance.sh presentation 'iPhone 17 Pro Max' '26.4'`와 `fps`가 기존 threshold를 그대로 통과한다: presentation 기존 latency, racing 300 sample 평균≥58fps·연속 2회<50 없음·first obstacle≥50. Memory는 사용자가 면제한 exportable trace gate 대신 동일 coordinator의 final idle RSS≤baseline 115%·last-five strict growth 없음·controller/scene 10/10 release summary를 반복 통과하고, runner exit 1의 유일 원인이 Xcode 26.4 `xctrace` Simulator attach/export blocker임을 evidence로 보존한다.
    - sensory acceptance에서 tick exactly 3+GO 1, 각 3/2/1 180ms accent와 GO 260ms visible event, collision→result 480...600ms, countdown/collision/result 중 racing FPS sample 0, route/retry cycle 동안 audio director identity 동일, stale cue/action 0, visual pool bound와 decoded audio≤8MiB를 `SG8_SENSORY_SUMMARY pass=true`로 검증한다.
    - compiled image 64MiB/max 2048와 production image/audio provenance SHA, iOS-only audio, Watch audio resource 0, Release DEBUG acceptance leakage 0, third-party dependency/background capability 0을 감사한다.
    - cold hub→settings toggle→maintenance vehicle/color→hub→Watch-ready 및 not-ready Cancel/Continue Touch→3·2·1·GO→steer/speed ramp→left/right near miss→collision→delayed result→Retry→background/foreground→Main Hub 전체 흐름을 normal/Reduced/system accessibility 조합과 두 iPhone 크기에서 확인한다.
    - protected gameplay audit가 `d07e593` 기준 `GameSimulation.swift`, `RoadProjection.swift`, `VehicleCatalog.swift` diff 0이고 steering packet fields/version, Watch readiness/router/calibration behavior가 보존됨을 확인한다.
    - `shasum -a 256 WatchCarRacer.xcodeproj/xcshareddata/xcschemes/WatchCarRacerWatchApp.xcscheme`가 `d84cce7bea7e7bf7b31cd7a92a0569bd293aa98829e69e77f2a3bad227884f6a`이고 `git diff --binary -- WatchCarRacer.xcodeproj/xcshareddata/xcschemes/WatchCarRacerWatchApp.xcscheme | shasum -a 256`가 `a7095007ccebc3c93b541413abdbc88f56b52bdaacfe0fcb66869bd713d78d35`인지 확인한다.
  - Depends on: SG1, SG2, SG3, SG4, SG5, SG6, SG7

## Final Verification

- `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' test`
- `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' test`
- iOS/watchOS Debug·Release 네 build가 모두 통과하고 Swift/Clang warning이 없다. AppIntents metadata-only note는 별도로 분류한다.
- SFX/haptics/effect settings는 defaults·persistence·independent gating과 accessibility precedence를 정확히 지킨다.
- audio manifest의 모든 role, format, provenance SHA, loop seam, decoded≤8MiB, node/one-shot bounds와 iOS-only membership이 통과한다.
- idle/mid/high engine, road/wind/tire scrub과 route ambience는 logical state/speed/steering에만 반응하며 interruption/background/Retry에서 중복·stale playback 없이 복구된다.
- near-miss side/grade/chain과 collision direction은 same-step presentation context에서만 계산되고 score/raw event/spawn/collision/steering은 `d07e593`와 동일하다.
- 3·2·1·GO는 simulation/input을 정지한 정확한 3초 sequence이며 설정에 맞는 iPhone/Watch cue를 한 번씩 fan-out한다.
- 3/2/1의 180ms accent와 GO의 260ms overlay가 Start Cue Contract대로 실제 render되고 Reduced/Reduce Motion 대체 표현 뒤 정확히 제거된다.
- collision result는 t=0 한 번 기록되고 480...600ms 뒤 표시된다. Retry/Hub/background가 stale collision task를 재생하거나 scene을 잘못 unpause하지 않는다.
- catch-up frame에서 event side/closeness는 final frame snapshot이 아니라 event가 발생한 substep snapshot을 사용하고, phase × lifecycle 전 조합이 Lifecycle Contract를 만족한다.
- Balanced/Reduced/Reduce Motion/Reduce Transparency 조합에서 판독성과 static information feedback이 유지되고 두 iPhone landscape layout과 AX semantics가 통과한다.
- existing presentation/FPS/texture threshold와 새 sensory summary가 모두 PASS다. Memory는 동일 runtime threshold summary가 PASS이고 exportable trace는 사용자 승인에 따라 non-blocking tooling follow-up이다.
- `WatchCarRacerWatchApp.xcscheme`의 file SHA-256 `d84cce7bea7e7bf7b31cd7a92a0569bd293aa98829e69e77f2a3bad227884f6a`와 binary-diff SHA-256 `a7095007ccebc3c93b541413abdbc88f56b52bdaacfe0fcb66869bd713d78d35`가 구현 전후 동일하다.
- 실제 iPhone speaker/headphone balance·silent switch·spatial accuracy, Phone/Watch haptic strength/skew, VoiceOver gesture, 20–30분 thermal/battery run은 non-blocking physical follow-up으로 기록한다.

## Progress

- 2026-08-29: `woohyuk-architect` 설계를 반영해 8개 subgoal draft를 작성함.
- 2026-08-29: `woohyuk-reviewer` 1차 BLOCKED의 audio self-authoring, same-step catch-up, start cue/lifecycle 표와 Watch scheme SHA 보존 요구를 모두 반영했고 revision round 1에서 APPROVE. 구현은 시작하지 않음.
- 2026-08-29: Ralph 실행을 시작하고 SG1 persistent sensory settings와 접근성 policy 구현에 착수함.
- 2026-08-29: SG1 구현 완료. 독립 tester가 focused 8/8 및 full iOS 134/134, runtime landscape/max AX settings flow, 접근성 policy 8조합, target membership, gameplay·Watch scheme 보호를 PASS로 확인함.
- 2026-08-29: SG2 구현 완료. 독립 tester가 15개 project-original PCM과 manifest/provenance, 두 clean run byte 재현성, 2.798MiB budget·peak/DC/seam 계약, focused 4/4, iOS/Watch Debug·Release bundle 격리와 보호 파일을 PASS로 확인함.
- 2026-08-29: SG3 구현 완료. 독립 tester가 AudioMix/Director 18/18, 영향 테스트 35/35, full iOS 155/155, actual AVAudioEngine graph 16-node/4 one-shot bound, 4-build matrix, readiness/runtime failure 분리와 보호 감사를 PASS로 확인함.
- 2026-08-29: SG4 구현 완료. 독립 tester가 same-step 5-step catch-up 반례, side/grade/3초 chain/150ms limiter, SFX·haptics gating, Watch cue round-trip·malformed isolation, iOS 165/165·Watch 13/13과 보호 계약을 PASS로 확인함.
- 2026-08-29: SG5 구현 완료. 독립 tester가 visual/policy focused 47/47, full iOS 170/170·Watch 13/13, 6,000-frame×2/100 near-miss/10 reset stress, fixed pool·cleanup·접근성 5모드와 4-build/protected audit를 PASS로 확인함.
- 2026-08-29: SG6 구현 완료. 독립 tester가 3→2→1→GO 3초/180·260ms cue 계약, t=0 immutable result와 520ms collision/lifecycle cancellation, Reduce Motion, iOS 178/178·Watch 13/13과 4-build/protected audit를 PASS로 확인함.
- 2026-08-29: SG7 구현 완료. 독립 tester가 changed/no-op/rejected selection·color cue, Watch-ready/Continue Touch의 성공 후 1회 Drive transition, hub/maintenance/game-session audio context 소유권, Reduce Motion/Transparency·Reduced 표현과 Pro Max/SE landscape·max AX를 검증했고 focused iOS 53/53, full iOS 184/184·Watch 13/13, 4-build/protected audit를 PASS로 확인함.
- 2026-08-29: SG8 구현과 2차 독립 검증에서 focused 27/27, full iOS 190/190·Watch 13/13, 4-build, presentation·FPS, Pro Max 26.4/SE 26.0의 Balanced·Reduced·system accessibility sensory matrix, memory runtime 10/10 release·RSS/trend와 보호 감사가 PASS함. 다만 Xcode 26.4 `xctrace` Simulator attach/export가 `Cannot find process for provided pid`와 `Document Missing Template Error`로 실패해 mandatory memory runner가 exit 1이므로 tester가 `BLOCKED`로 판정함. SG8은 미완료로 보존함.
- 2026-08-29: 사용자가 exportable `xctrace` gate 면제와 반복 통과한 runtime memory summary 대체를 승인해 Ralph를 재개함. SG8 재검증과 전체 Final Verification을 대기함.
- 2026-08-29: SG8 재검증 PASS. 독립 tester가 면제가 Xcode 26.4 Instruments attach/export에만 적용되고 RSS≤baseline 115%·last-five strict growth 없음·controller/scene 10/10 release는 반복 PASS함을 확인했다. Focused 27/27, full iOS 190/190·Watch 13/13, 4-build, 두 기기 sensory/accessibility matrix, presentation/FPS, asset/protected audit도 PASS함.
- 2026-08-30: 전체 Final Verification PASS. 독립 tester가 fresh full iOS 190/190·Watch 13/13, clean DerivedData 4-build, Pro Max 26.4 Balanced/Reduced sensory, presentation, audio 재생성, asset/Release/protected 감사와 최신 유효 FPS·runtime memory evidence를 종합 검증했다. 사용자가 면제한 exportable xctrace와 실물 sensory/thermal/VoiceOver gesture만 non-blocking follow-up으로 남김.

## Risks

- **Project-original audio 품질:** 외부 source를 기다리지는 않지만 offline authoring 결과가 기술 gate만 통과하고 음색은 빈약할 수 있다. SG2의 deterministic recipe·role별 layer·seam/peak/DC 검사를 차단 조건으로 두고 실제 speaker/headphone mix tuning은 명시적 physical follow-up으로 남긴다.
- **Audio render-thread 비용:** node/buffer 생성·decode를 frame path에서 하면 60fps가 흔들릴 수 있다. app-lifetime preallocated graph, ≤30Hz finite parameter update와 bounded pool을 사용한다.
- **Loop seam/음량 불일치:** 세 engine layer와 ambience가 crossfade 중 phasing/click을 만들 수 있다. format/loop seam/peak test와 실제 device follow-up을 분리한다.
- **Collision task race:** delayed result가 Retry/Hub/background 뒤 나타날 수 있다. countdown과 별도의 generation token/cancellable task를 사용하고 t=0 immutable result만 보존한다.
- **Render/action 충돌:** recoil action 중 normal render가 node position을 덮어쓸 수 있다. crashed final snapshot 뒤 simulation transform과 presentation transform을 분리한다.
- **속도 효과 overdraw:** fog/streak/debris가 60fps를 해칠 수 있다. texture/filter 없이 fixed pool과 hard node bounds를 사용한다.
- **접근성 충돌:** user Balanced가 system Reduce Motion을 무시할 수 있다. system clamp를 항상 마지막에 적용하고 조합 table test로 고정한다.
- **Watch cue 호환성:** 새 feedback kind를 구버전 Watch가 decode하지 못할 수 있다. steering packet/version은 유지하고 cue failure를 격리하며 같은 release의 paired app을 기준으로 test한다.
- **의미 없는 combo 오해:** presentation chain이 score multiplier처럼 보일 수 있다. 점수 text는 원래 `+100`만 표시하고 chain은 감각 tier로만 표현한다.
- **기존 사용자 변경 손상:** Watch scheme formatting-only diff가 있다. 모든 staging/verification에서 해당 파일을 보존하고 baseline audit 대상에서 제외한다.

## Open Questions

- None.

## Implementation Result

Implemented on 2026-08-30.

### Summary

- 영속 sensory 설정, project-original audio kit, app-lifetime dynamic audio, 방향성 near-miss, 속도감 visual, 3·2·1·GO, collision choreography와 hub/maintenance micro-interaction을 통합했다.
- 기존 simulation·score·spawn·difficulty·steering protocol을 보존하고 Balanced/Reduced·Reduce Motion/Transparency·SFX/haptics gating을 일관되게 적용했다.
- DEBUG sensory acceptance가 실제 cue lifecycle, collision latency, route/Watch branch, lifecycle, 양방향 near-miss, pool/audio/memory 경계를 자동 검증한다.

### Completed Subgoals

- [x] SG1: persistent sensory settings/accessibility policy.
- [x] SG2: deterministic original audio assets/manifest/provenance.
- [x] SG3: app-lifetime dynamic audio engine/lifecycle.
- [x] SG4: same-step directional feedback/Watch cue contract.
- [x] SG5: speed and near-miss visual presentation layer.
- [x] SG6: exact start ritual/cancellable collision choreography.
- [x] SG7: route ambience/success-only maintenance and Drive interactions.
- [x] SG8: full sensory regression/performance/runtime-memory acceptance.

### Changed Files

- `Scripts/build_original_audio_assets.swift`, `WatchCarRacer/iOS/Resources/Audio/`, `docs/assets/provenance.md`: original audio build, shipped assets and provenance.
- `WatchCarRacer/iOS/Sensory/`: settings, accessibility policy, audio asset/mix/director implementation.
- `WatchCarRacer/iOS/App/`: app-owned dependencies, route ambience, maintenance/Drive interactions, cue/collision lifecycle and acceptance coordinator.
- `WatchCarRacer/iOS/Feedback/`, `WatchCarRacer/iOS/Game/`, `WatchCarRacer/Shared/`, `WatchCarRacer/Watch/`: directional feedback, bounded presentation pools, cue transport and Watch haptics.
- `WatchCarRacerTests/`, `WatchCarRacerWatchTests/`, `WatchCarRacer.xcodeproj/project.pbxproj`: focused regression/acceptance tests and target membership.
- `Scripts/run_sg6_acceptance.sh`: presentation, FPS, memory and sensory runner modes.

### Verification

- Focused iOS: 27/27 passed.
- Full iOS/watchOS: 190/190, 13/13 passed.
- iOS/watchOS Debug·Release: four builds passed; Swift/Clang warning 0.
- Presentation/FPS: passed; FPS 300 samples, average 59.997, minimum 59.
- Sensory matrix: iPhone 17 Pro Max iOS 26.4·iPhone SE iOS 26.0의 Balanced, Reduced, Reduce Motion/Transparency cold runs passed.
- Memory runtime: `finalBytes=354254848 <= thresholdBytes=407280025`, strict growth false, controller/scene release 10/10 passed. Xcode 26.4 xctrace export는 사용자 승인에 따라 non-blocking tooling follow-up이다.
- Audio/assets: 15 WAV, 48kHz Int16, decoded ≈2.8MiB, node 16, iOS-only membership, compiled image 57.114MiB/max 2048, provenance SHA passed.
- Protected audit: `GameSimulation.swift`, `RoadProjection.swift`, `VehicleCatalog.swift` baseline diff 0; Watch scheme file/binary-diff SHA exact; Release acceptance leakage, third-party/background capability 0.
- Final independent tester: PASS.

### Follow-ups

- Exportable Xcode Instruments Game Memory trace when Simulator attach/export becomes available.
- 실제 iPhone speaker/headphone/silent switch/spatial balance, Phone/Watch haptic strength/skew, VoiceOver gesture, 20–30분 thermal/battery run.
