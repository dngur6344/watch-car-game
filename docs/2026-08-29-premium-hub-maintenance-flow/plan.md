---
title: "프리미엄 익스프레스 허브와 차량 정비 UX"
status: implemented
created: 2026-08-28
updated: 2026-08-29
implemented_at: 2026-08-29
target_repo: "/Users/woohyuk/Desktop/watch-car-racer"
goal_size: large
feature_slug: "premium-hub-maintenance-flow"
---

# 프리미엄 익스프레스 허브와 차량 정비 UX

## Goal

현재 차고 중심 진입 흐름을 도로로 바로 이어지는 프리미엄 익스프레스 메인 허브로 개편하고, 별도 `VEHICLE MAINTENANCE` 화면에서 차량 외형을 편집하도록 분리한다. Watch 준비 안내, 3·2·1 출발, local best와 개선된 결과 화면을 하나의 빠르고 명확한 아케이드 흐름으로 연결하면서 기존 결정론적 게임·Watch/touch fallback·차량 공정성을 유지한다.

## Assumptions

- 메인 허브는 `.woohyuk/design-references/main-expressway-portal.png`의 도로 몰입감과 `.woohyuk/design-references/watch-readiness-workshop.png`의 명확한 Watch 상태 위계를 결합한다. 레퍼런스 좌표를 그대로 복제하지 않고 실제 iPhone landscape safe area와 Dynamic Type에 맞춘다.
- 차량 정비 화면은 `.woohyuk/design-references/maintenance-pit-lane.png`의 조명·차량 중심 위계를 사용하되 실제 브랜드, baked text/control과 레퍼런스의 3D 차량을 복제하지 않는다. 기존 Rally Hatch, GT Coupe, Angular Performance identity를 유지하는 original presentation art를 제작한다.
- visual fidelity를 위해 text/control/vehicle가 baked되지 않은 hub·pit-lane 배경과 차량별 tint 가능한 presentation hero layer가 필요하다. 이 art는 route-lazy presentation resource로 관리하고 기존 gameplay atlas preload에는 넣지 않는다.
- 실제 iPhone/Apple Watch의 손목 자세, packet 지연, 햅틱, 화면·배터리 수명과 real VoiceOver gesture 검증은 기존 비차단 physical-device follow-up으로 유지한다.
- 현재 검증 환경인 Xcode 26.4, iPhone 17 Pro Max iOS 26.4, iPhone SE (3rd generation) iOS 26.0, Apple Watch Series 11 (46mm) watchOS 26.4를 사용한다.

## Decisions

- 사용자 결정: 기본 진입 화면은 Expressway Portal과 Precision Workshop을 혼합한 메인 허브다.
- 사용자 결정: 메인 허브의 `VEHICLE MAINTENANCE` 버튼이 별도 Cinematic Pit Lane 차량 정비 화면을 연다.
- 사용자 결정: 차량 정비는 현재 차량 3종×색상 8종의 외형 편집만 제공한다. 차량 성능·조향·충돌·난이도는 모두 동일하며 휠·데칼·파츠·튜닝은 추가하지 않는다.
- 사용자 결정: 정비에서 변경한 값은 draft이며 Back/Done으로 메인 허브에 돌아와도 저장하지 않는다. 메인 허브의 `DRIVE`가 성공할 때만 선택을 저장하고 committed selection으로 확정한다.
- 사용자 결정: 이번 범위에는 메인 허브, 차량 정비, Watch 준비 안내 sheet, 3·2·1 countdown, 개선된 collision/result 화면과 local best를 포함한다. 별도 기록·통계 화면은 만들지 않는다.
- 사용자 결정: Watch가 준비되지 않은 상태에서 `DRIVE`를 누르면 안내 sheet를 열고 저장·session 생성을 보류한다. `CONTINUE WITH TOUCH`를 선택한 경우에만 원래 Drive intent를 이어서 commit하고 출발하며, 취소하면 아무 상태도 저장하지 않는다.
- 사용자 결정: 충돌 후 `RETRY`도 동일 controller·appearance·seed·`SessionControlRoute`를 유지한 채 3·2·1 countdown을 다시 실행한다.
- `SessionControlRoute`는 `.adaptiveWatchPreferred`와 `.touchOnly` 두 값만 둔다. Watch-ready 상태에서 직접 Drive하면 adaptive route를 사용해 기존 Watch 우선·touch fallback/명시적 touch takeover 규칙을 유지하고, `CONTINUE WITH TOUCH`는 해당 attempt와 모든 Retry를 touch-only로 고정해 도중 Watch가 ready가 되어도 자동 승격하지 않는다.
- iOS가 inactive/background가 되면 playing session의 scene을 즉시 pause하고 countdown task를 취소한다. active 복귀 시 기존 countdown 또는 racing attempt는 score·거리·seed·appearance·control route를 reset하지 않고 새 3·2·1부터 재개하며, result는 result로 복원하고 simulation을 재개하지 않는다.
- countdown과 result는 top-level `GamePhase`가 아니라 `GameSessionController`의 presentation state로 소유한다.
- Watch calibration 권한은 Watch 앱에만 둔다. iPhone은 read-only readiness를 표시하고 calibration·synthetic input command를 보내지 않는다.
- 사용자 승인(2026-08-28): built-in imagegen이 만든 배경과 real-alpha 차량 master를 Swift/CoreGraphics로 deterministic 후처리해 paint mask/details-shadow를 분리하고 sRGB RGBA로 정규화할 수 있다. 생성 원본은 provenance에 유지하고 후처리 규칙·SHA를 기록한다.

## Scope

- `AppFlowController.Route`를 `.hub`, `.maintenance`, `.playing`으로 개편하고 cold launch는 항상 `.hub`로 시작한다.
- committed selection과 draft selection을 분리하고 maintenance 진입·Back/Done·Drive 실패·app relaunch의 정확한 상태 규칙을 구현한다.
- local best 전용 versionless integer store와 한 attempt당 한 번만 기록되는 result contract를 추가한다.
- Expressway main hub, Pit Lane maintenance, Watch readiness sheet, countdown overlay와 result overlay를 SwiftUI로 구성한다.
- Watch activation/reachability/packet/calibration/motion/stale 상태를 기존 router 우선순위와 동일한 semantic readiness로 투영한다.
- presentation-only PNG kit, Xcode target membership, asset manifest/provenance와 texture-memory 검사를 확장한다.
- countdown task cancellation, scene phase pause/re-entry, scene pause/unpause, touch input gating, Retry와 Hub 복귀 시 controller·scene 수명을 정리한다.
- hub·maintenance·countdown·result의 Dynamic Type, VoiceOver semantics, Reduce Motion, Reduce Transparency와 양쪽 landscape layout을 검증한다.
- 기존 DEBUG acceptance coordinator를 새 route/countdown에 맞게 갱신하고 FPS·memory regression을 다시 검증한다.

## Out Of Scope

- currency, shop, unlock, inventory, missions, map/biome selection, ads, payments, account, online leaderboard와 cloud sync.
- 차량별 성능, handling, speed, collision box, difficulty, spawn 또는 score 차이.
- 신규 차량, 신규 body color, 휠·데칼·라이트·파츠 customization.
- 별도 records/statistics 화면, achievement, run history와 상세 telemetry.
- iPhone에서 Watch를 원격 보정하거나 합성 steering을 production에 제공하는 기능.
- App Intents, Game Center, HealthKit, workout session, extended runtime, background capability 또는 third-party runtime dependency.
- `GameSimulation`, `RoadProjection`, Watch packet protocol과 Watch calibration engine의 규칙 변경.

## Current Evidence

- Git: `main`의 `f4cd9d6`이며 planning 시작 시 tracked working tree가 clean하다.
- `WatchCarRacer/iOS/App/AppFlowController.swift`: 현재 route는 `.garage/.playing` 두 개이고 launch 시 store selection을 하나의 draft로 읽으며 controller 생성 성공 뒤에만 저장한다.
- `WatchCarRacer/iOS/App/AppRootView.swift`: GarageView와 GameRootView만 전환하는 route shell이다.
- `WatchCarRacer/iOS/App/GarageView.swift`: 차량 3종×색상 8종 picker, preview와 `DRIVE`를 한 화면에서 소유한다.
- `WatchCarRacer/iOS/App/GameSessionController.swift`: Retry는 같은 controller·scene·seed·appearance를 유지하지만 countdown/result presentation state는 없다.
- `WatchCarRacer/iOS/Game/GameScene.swift`: scene attach 후 fixed-step simulation이 즉시 진행되므로 countdown 중 명시적으로 pause해야 한다.
- `WatchCarRacer/iOS/Input/PhoneWatchSession.swift`: iPhone이 소비할 read-only Watch routing reading과 activation/reachability 정보를 이미 소유한다.
- `WatchCarRacer/Watch/App/SteeringControlView.swift`, `WatchCarRacer/Watch/Connectivity/WatchControllerSession.swift`, `WatchCarRacer/Watch/Motion/MotionSteeringEngine.swift`: calibration은 Watch process에서만 수행한다.
- `WatchCarRacer/iOS/Customization/VehicleCatalog.swift`: 외형 전용 차량 3종×색상 8종과 24개 유효 조합을 정의한다.
- `WatchCarRacer/iOS/Resources/AssetManifest.json`, `GameAssetLibrary.swift`: 19개 PNG와 app-owned serial preload/cache 계약이 있다.
- `WatchCarRacer.xcodeproj/project.pbxproj`: application/unit-test target만 있고 UI-test target은 없다. 이번 계획은 sheet mutation을 별도 flow model로 이동해 unit test하고 gesture wiring은 source/visual/AX evidence로 감사한다.
- `docs/2026-08-25-premium-assets-garage-customization/plan.md`: 현재 baseline은 iOS 87/87, watchOS 11/11, 네 Debug·Release build, FPS 평균 59.932/min 58, texture 21.11MiB/max 2048, 10회 route transition memory PASS다.
- `.woohyuk/design-references/main-expressway-portal.png`: main hub의 road-first visual hierarchy 기준.
- `.woohyuk/design-references/watch-readiness-workshop.png`: Watch readiness와 selection hierarchy 기준. 레퍼런스의 Settings·성능 문구·iPhone calibration action은 범위 밖이다.
- `.woohyuk/design-references/maintenance-pit-lane.png`: maintenance의 large vehicle hero와 cinematic lighting 기준.

## Subgoals

- [x] SG1: 세 route flow, draft/commit과 local-best 상태 계약 구현
  - Outcome: 앱은 항상 Expressway hub로 열리고, maintenance의 draft는 Back/Done 뒤 hub에서 유지되지만 app relaunch 전까지 저장되지 않으며 성공한 Drive만 정확히 한 번 commit한다. local-best store는 유효 점수를 단조 증가시키고 immutable `RunResult` 값 모델은 한 attempt의 결과 snapshot을 표현한다.
  - Work: `AppFlowController.swift`를 `.hub/.maintenance/.playing` route와 `committedSelection`/`draftSelection` 소유 구조로 개편한다. `LocalBestScoreStore.swift`, 값 전용 `RunResult`와 `SessionControlRoute`를 추가하고 `WatchCarRacerApp.swift`에서 app-owned store를 주입한다. maintenance enter/exit, Drive 성공·실패, Retry, Hub release API를 명시한다. collision transition과 attempt별 record guard는 SG5가 소유한다.
  - Verify:
    - `AppFlowControllerTests`에서 cold launch hub, maintenance enter, selection edit, Back/Done 후 draft 유지·save 0회, 재진입 draft 복원, app 재생성 시 committed 복원, Drive 성공 save 1회, asset/controller failure save 0회, Retry controller/scene/seed/appearance 동일, Hub 복귀 weak controller/scene 해제를 검사한다.
    - `LocalBestScoreStoreTests`에서 empty→0, 음수·손상 값 self-heal, higher score만 write, lower/equal no-write를 검사하고, `RunResult` 값 테스트에서 score·previous best·local best·isNewBest가 생성 뒤 변하지 않는지 검사한다. collision attempt당 1회 기록은 SG5에서 검증한다.
    - 기존 `VehicleSelectionStoreTests`, `VehicleCatalogTests`와 `GameSimulationTests`가 수정 없이 통과한다.
  - Depends on: None

- [x] SG2: 기존 입력 우선순위와 일치하는 read-only Watch readiness 추가
  - Outcome: 메인 허브는 activating, disconnected, awaiting packet, needs calibration, motion unavailable, stale, ready를 정확히 구분하고 실제 Watch가 준비되지 않았을 때 touch fallback 안내를 제공한다.
  - Work: `PhoneWatchSession.swift`에 semantic `WatchReadinessStatus` projection을 추가하고 기존 activation/reachability/packet state에서 계산한다. Watch readiness sheet의 copy/model seam을 정의하되 iPhone→Watch calibration command나 synthetic input mutation은 추가하지 않는다.
  - Verify:
    - `PhoneWatchSessionTests`에서 activation·reachability·packet status·freshness 조합의 전체 table과 판정 우선순위를 검사한다.
    - `ready` 조건이 `SteeringInputRouter`가 fresh Watch input을 선택하는 조건과 일치하고, stale/unreachable 상태에서 touch fallback이 유지되는지 검사한다.
    - `git diff --exit-code f4cd9d6 -- WatchCarRacer/Shared/ControllerMessages.swift WatchCarRacer/Watch/Connectivity/WatchControllerSession.swift WatchCarRacer/Watch/Motion/MotionSteeringEngine.swift`로 Watch packet/calibration production 경계가 변경되지 않았음을 확인한다.
    - iPhone production API와 UI에 calibrate/recalibrate/synthetic steering mutation이 없음을 source audit한다.
  - Depends on: None

- [x] SG3: hub·maintenance presentation PNG kit과 resource 계약 구성
  - Outcome: 두 화면은 선택한 차량 identity와 색을 유지하는 original premium art로 렌더링되며 text/control이 background에 baked되지 않고 texture budget을 넘지 않는다.
  - Work: `WatchCarRacer/iOS/Resources/Presentation/`에 차량·UI가 없는 Expressway Portal와 Pit Lane background를 추가한다. 세 차량별 large hero를 tint 가능한 paint layer와 authored details/shadow layer로 구성한다. 기존 `AssetManifest.json`은 gameplay-only 19개 계약으로 유지하고 신규 `PresentationAssetManifest.json`을 별도로 둔다. `GameAssetLibrary`와 `preloadGameplayTextures()`는 presentation manifest를 참조하지 않으며, 별도 route-lazy SwiftUI presentation loader/factory만 현재 route의 background와 선택 차량 hero layer를 decode한다. 두 manifest의 provenance, Xcode iOS-only resource membership과 texture-memory script를 확장한다.
  - Verify:
    - `PresentationAssetTests`에서 expected background 2개와 hero 3종×2 layer의 존재·nonzero decode·stable name·pixel 크기·8-bit sRGB RGBA·pivot/alpha 계약을 검사한다.
    - decoder spy와 fresh cache를 사용해 `GameAssetLibrary.preloadAll()`/`preloadGameplayTextures()` 완료 뒤 presentation decode count가 0이고, `AssetManifest.json`에 presentation path/name이 0개이며, hub 진입은 hub background+선택 hero만, maintenance 진입은 pit-lane background+선택 hero만 lazy decode하는지 검사한다.
    - hero 3종×8색 24조합 capture에서 paint만 tint되고 glass/light/shadow/detail이 보존되며 gameplay 차량과 같은 identity임을 확인한다.
    - production PNG 전부가 provenance에 있고 실제 SHA-256과 일치하며 logo, baked copy/control, 외부/브랜드 asset이 없음을 검사한다.
    - fresh Debug app에서 compiled atlas/background/presentation decoded allocation이 64MiB 이하, 어떤 page/standalone image도 2048×2048 이하인지 `Scripts/measure_compiled_texture_memory.swift`로 검사한다.
    - Watch app bundle에 presentation/gameplay iOS PNG, atlas와 manifest가 0개인지 검사한다.
  - Depends on: None

- [x] SG4: Expressway main hub, Pit Lane maintenance와 Watch 안내 sheet 완성
  - Outcome: 사용자는 cold launch hub에서 마지막 committed 차량과 local best·Watch 상태를 보고, maintenance에서 3×8 외형을 draft로 편집한 뒤 hub로 돌아와 Watch 준비 여부에 맞는 한 번의 명확한 `DRIVE` 흐름으로 출발한다.
  - Work: 기존 `GarageView.swift`를 `MainHubView.swift`로 대체하고 `VehicleMaintenanceView.swift`, `VehiclePresentationView.swift`, `WatchReadinessSheet.swift`를 추가한다. `AppRootView.swift`가 hub/maintenance/playing을 전환하고 shared asset library와 Watch session 수명을 유지한다. hub에는 picker를 두지 않고 `VEHICLE MAINTENANCE`, Watch status, local best, `DRIVE`만 둔다. maintenance에는 정확히 3 vehicle·8 color, Back/Done과 pending-until-Drive 설명만 둔다. UI mutation을 직접 분산하지 않고 unit-testable `HubDriveIntentController`가 pending Drive sheet intent를 소유한다. Watch-ready Drive는 `.adaptiveWatchPreferred`로 즉시 시작하고, not-ready Drive는 저장·session 없이 sheet intent만 만들며, Cancel·interactive sheet dismissal은 같은 cancel API로 intent를 지우고, `CONTINUE WITH TOUCH`만 intent를 한 번 소비해 `.touchOnly` session을 commit/start한다.
  - Verify:
    - `HubDriveIntentControllerTests`와 `AppFlowControllerTests`에서 Watch-ready direct Drive→adaptive route, Watch-not-ready→pending sheet/save 0/session 0, button Cancel→intent clear/no-op, SwiftUI `.sheet(onDismiss:)`가 호출하는 interactive-dismiss API→intent clear/no-op, Continue With Touch의 single-consume→touch-only route/save 1/session 1개, dismiss 뒤 stale Continue 호출 no-op을 검사한다.
    - AppFlow/controller test에서 maintenance 3×8 state source, Back/Done draft retention, no-save, pending text/AX value를 검사하고, hub picker 부재와 sheet gesture wiring은 source audit 및 SG6 screenshot/Simulator Accessibility Inspector evidence로 확인한다. 이번 범위에 XCUITest target은 추가하지 않는다.
    - asset loading 중 Drive 차단·retry와 error copy가 유지되고 중복 preload/controller/session activation이 없는지 검사한다.
    - iPhone 17 Pro Max iOS 26.4와 iPhone SE (3rd generation) iOS 26.0의 양쪽 landscape에서 safe area, short-height fallback, hero crop, controls와 sheet가 잘리거나 겹치지 않는지 capture한다.
    - 최대 Dynamic Type, Reduce Motion, Reduce Transparency에서 vehicle/name/status/primary actions가 사용 가능하고 horizontal scroll에 primary action이 숨지 않는지 확인한다.
    - 모든 차량·색상·status·Back/Done/Drive/Continue control이 44×44pt 이상이고 label/value/hint, selected trait, checkmark/outline으로 색상 외 상태를 전달하는지 accessibility audit한다.
  - Depends on: SG1, SG2, SG3

- [x] SG5: cancellable 3·2·1 countdown과 local-best result UX 통합
  - Outcome: 최초 Drive와 모든 Retry는 scene·score·거리·입력이 정지된 3·2·1을 거쳐 시작하고, collision 후 score/local best/new best와 Retry/Main Hub가 명확하게 표시된다.
  - Work: `GameSessionController.swift`에 `RunPresentationPhase`, immutable `SessionControlRoute`, injectable countdown sleeper/generation token/cancellation과 attempt별 result guard를 추가한다. session 생성과 Retry는 scene reset→pause→3·2·1→unpause 순서를 지키고 Retry는 route를 다시 판정하지 않는다. `.touchOnly`에서는 Watch reading이 active가 되어도 router promotion을 허용하지 않고, `.adaptiveWatchPreferred`만 기존 Watch 우선/fallback/touch-takeover 동작을 사용한다. collision transition에서 result recorder를 한 번 호출한다. `WatchCarRacerApp.swift`/`AppRootView.swift`가 `scenePhase`를 controller의 explicit lifecycle API로 전달한다. inactive/background에서는 task cancel+scene pause, active 복귀 시 countdown/racing은 같은 attempt 상태에서 새 3·2·1, result는 paused result 유지로 처리한다. `GameRootView.swift`에 countdown/result overlay와 focus semantics를 구현하고 `.racing`에서만 touch update를 허용한다. `GameScene.swift`에 Reduce Motion preference를 전달해 world shake를 억제하되 flash·label·audio·haptic은 유지한다.
  - Verify:
    - `GameSessionControllerTests`에서 countdown 3→2→1 순서, 각 tick 동안 elapsed time·distance·score·obstacle·steering read 불변, 완료 뒤 한 번만 unpause, touch input 차단을 fake sleeper/clock으로 검사한다.
    - Watch-ready Drive가 adaptive route, Continue With Touch가 touch-only route를 선택하는지 검사한다. Retry 전후 Watch readiness를 ready↔stale 양방향으로 바꿔도 동일 controller/scene/seed/appearance/control route가 유지되고, touch-only가 fresh Watch를 자동 채택하지 않으며 adaptive가 기존 router 전환을 유지하는지 검사한다.
    - scene-phase table test에서 countdown→inactive는 task cancel/paused, racing→inactive는 현재 attempt state 보존/paused, result→inactive는 result 보존, active 복귀 시 countdown·racing은 reset 없이 3부터 재시작하고 result는 racing으로 돌아가지 않는지 fake sleeper/clock으로 검사한다.
    - background/Hub 전환·빠른 Retry에서 오래된 task가 scene을 unpause하지 않고, 두 번 연속 active notification이 countdown task를 중복 생성하지 않으며, Hub 뒤 task/controller/scene이 해제되는지 검사한다.
    - collision transition당 local-best record 1회, result의 final score·previous best·local best·isNewBest 고정, lower score no-write를 검사한다.
    - result overlay에서 Retry와 Main Hub가 각각 countdown 재시작과 session 해제를 수행하고 VoiceOver heading/focus와 결합 score value가 제공되는지 검사한다.
    - Reduce Motion에서 countdown zoom/pulse와 world shake가 없고 collision 정보, flash, audio/haptic과 result action은 유지되는지 확인한다.
  - Depends on: SG1, SG2, SG4

- [x] SG6: 전체 regression·visual·performance·memory acceptance
  - Outcome: 새 허브·정비·Watch 안내·countdown·result 흐름이 기존 Watch/touch 주행을 회귀시키지 않고 short landscape와 반복 route 전환에서도 약 60fps와 안정된 memory를 유지한다.
  - Work: `SG6AcceptanceCoordinator.swift`를 `.hub/.maintenance/.playing` 및 countdown-aware route로 갱신한다. 기존 `--sg6-fps`는 `.racing` 중 GameScene이 실제 update한 1초 FPS만 수집하도록 하고, 별도 `--sg6-presentation` mode와 app-start monotonic probe를 추가해 hub first layout, lazy hero ready, route render, Drive→countdown과 실제 countdown tick을 측정한다. `Scripts/run_sg6_acceptance.sh`는 mode/device/OS를 받아 Debug build·boot/install/launch·unified-log summary polling·timeout·evidence 저장을 수행하고 summary 실패나 누락 시 nonzero로 종료한다. 발견된 결함만 소유 모듈에서 수정하고 모든 visual/accessibility/runtime evidence를 `.woohyuk/` 아래에 정리한다.
  - Verify:
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' test`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' test`
    - iOS/watchOS simulator의 Debug·Release 네 build가 Swift/Clang warning 없이 통과하고 AppIntents metadata-only note를 별도 분류한다.
    - `git diff --exit-code f4cd9d6 -- WatchCarRacer/iOS/Game/GameSimulation.swift WatchCarRacer/iOS/Game/RoadProjection.swift WatchCarRacer/Shared/ControllerMessages.swift WatchCarRacer/Watch/Connectivity/WatchControllerSession.swift WatchCarRacer/Watch/Motion/MotionSteeringEngine.swift WatchCarRacer/iOS/Customization/VehicleCatalog.swift WatchCarRacer/iOS/Customization/VehicleSelectionStore.swift`로 gameplay·protocol·catalog baseline을 보존한다.
    - cold launch hub→maintenance 24 preview→hub→Watch-ready Drive와 not-ready Cancel/Continue Touch→3·2·1→touch/Watch run→near miss→collision→result→Retry 3·2·1→collision→Main Hub→relaunch committed selection/local best 복원을 확인한다.
    - hub, maintenance, Watch readiness 전 상태, 3/2/1, normal result와 new-best result를 두 iPhone 크기·양쪽 landscape·최대 Dynamic Type·Reduce Motion·Reduce Transparency에서 screenshot/AX audit한다.
    - `Scripts/run_sg6_acceptance.sh presentation 'iPhone 17 Pro Max' '26.4'`: cold launch→hub first layout 1,500ms 이하, hub→maintenance hero-ready 500ms 이하, maintenance→hub ready 250ms 이하, accepted Drive→rendered countdown(3) 250ms 이하, 실제 3→2→1 각 interval 850...1,150ms와 countdown(3)→racing 총 2,850...3,150ms를 `SG6_PRESENTATION_SUMMARY pass=true` 한 줄로 검증한다. 배경/hero decode 완료 전 ready event를 기록하지 않고 각 route는 cold 1회·warm 3회 측정하며 모두 threshold를 만족해야 한다.
    - `Scripts/run_sg6_acceptance.sh fps 'iPhone 17 Pro Max' '26.4'`: countdown sample은 제외하고 `.racing` 중 GameScene update가 만든 첫 300개 1초 sample 평균 58fps 이상, 연속 2회 50fps 미만 없음, first-obstacle sample 50fps 이상, freeze/state loss 없음과 `SG6_FPS_SUMMARY pass=true`를 검증한다.
    - `Scripts/run_sg6_acceptance.sh memory 'iPhone 17 Pro Max' '26.4'`: 한 연속 Allocations/VM trace에서 preload 완료 후 hub→maintenance→hub→Drive→countdown→collision→Retry→countdown→collision→Main Hub 1회 warm-up, Hub 10초 idle baseline을 기록한다. 동일 cycle 10회 뒤 final 10초 idle RSS가 baseline의 115% 이하이고 마지막 다섯 표본이 계속 증가하지 않으며 controller/scene 10/10이 해제되고 `SG6_MEMORY_SUMMARY pass=true`여야 한다.
    - production PNG provenance SHA, decoded 64MiB, max 2048, iOS-only target membership, no logo/service/capability/runtime dependency와 Release의 DEBUG acceptance 부재를 최종 감사한다.
  - Depends on: SG1, SG2, SG3, SG4, SG5

## Final Verification

- SG6의 exact iOS/watchOS full tests와 iOS/watchOS Debug·Release 네 build가 모두 통과하고 Swift/Clang warning이 없다.
- 앱은 매 launch 시 Expressway hub로 시작하고 maintenance Back/Done은 draft를 유지하되 저장하지 않으며 성공한 Drive만 committed selection을 저장한다.
- Watch ready이면 adaptive Watch-preferred route로 직접 Drive하고, not ready이면 sheet에서 Cancel/interactive dismissal은 무효·Continue With Touch만 touch-only route로 commit/start한다.
- 최초 Drive와 모든 Retry는 정지된 3·2·1을 거쳐 출발한다. Retry는 동일 controller/appearance/seed/control route를 유지하고, 오래된 countdown task가 background·Hub·새 Retry 뒤 scene을 unpause하지 않는다.
- background 복귀 시 countdown/racing은 같은 attempt의 score·거리·seed를 보존한 새 3·2·1로 재개하고 result는 result에 머문다.
- collision은 attempt당 result를 한 번 만들고 local best를 단조 증가시키며 Main Hub는 controller/scene 해제를 보장한다.
- hub/maintenance presentation art는 기존 3차량 identity와 8색을 보존하고 gameplay stat·collision·spawn·score·difficulty·Watch/touch 결과를 바꾸지 않는다.
- two-device/both-landscape, maximum Dynamic Type, Reduce Motion, Reduce Transparency와 Simulator AX semantics에서 hero·status·selection·sheet·countdown·result action이 잘리거나 색상에만 의존하지 않는다.
- presentation/gameplay decoded allocation 64MiB, max 2048, provenance SHA, iOS-only resources와 원본성 계약이 통과한다.
- 별도 presentation latency, active-gameplay 300초 FPS와 10-cycle route trace가 SG6 threshold를 만족하고 금지 dependency·capability·service·DEBUG Release leakage가 없다.
- 실제 iPhone/Apple Watch VoiceOver gesture, posture, latency, haptics, display/battery lifetime은 기존 physical-device follow-up으로 남으며 이번 simulator 완료를 차단하지 않는다.

## Progress

- 2026-08-28: `woohyuk-architect` 분석과 두 차례의 plan revision을 거쳐 `woohyuk-reviewer` PLAN_REVIEW에서 APPROVE. 구현은 시작하지 않음.
- 2026-08-28: Ralph 실행 시작. status를 `in-progress`로 전환하고 SG1 구현·독립 검증 queue를 시작함.
- 2026-08-28: SG1 완료. 2차 tester에서 PASS—hub/maintenance/playing 상태, draft/commit, local best/RunResult 계약과 production maintenance bridge를 검증했고 focused iOS test 41/41, pbxproj lint, diff check, 보호 baseline audit가 통과함.
- 2026-08-28: SG2 완료. tester PASS—Watch readiness 우선순위와 250/251ms freshness 경계, router 동치·touch fallback을 16/16 focused test로 검증했고 shared packet/Watch calibration 보호 파일 diff가 0임을 확인함.
- 2026-08-28: SG3 BLOCKED. built-in imagegen으로 고품질 배경 2장과 real-alpha 차량 master 3종은 생성했으나 Rally paint 3회·details 1회 분리 편집이 모두 baked checkerboard RGB(`hasAlpha: no`)로 실패함. imagegen 지침과 SG3 fallback 규칙에 따라 로컬 bitmap 분리/변환을 임의 사용하지 않고 중단했으며 SG4 이후는 시작하지 않음.
- 2026-08-28: 사용자가 Swift/CoreGraphics deterministic bitmap 후처리를 명시적으로 승인함. status를 `in-progress`로 복원하고 기존 generated-image 원본을 사용해 SG3부터 Ralph를 재개함.
- 2026-08-28: SG3 완료. tester 2차 PASS—Swift/CoreGraphics로 분리한 presentation PNG 8개와 injectable route-lazy loader/cache를 검증했고 focused test 20/20, Debug build, iOS-only bundle audit, provenance SHA, 57.11MiB/64MiB decoded allocation과 max 2048px가 통과함.
- 2026-08-28: SG4 완료. tester PASS—Expressway hub, Pit Lane maintenance, Watch readiness sheet와 single-consume Drive intent를 검증했고 focused test 49/49, Pro Max/SE Debug build, 3×8 AX tree, SE AXXXL compact layout과 24조합 transparent tint 합성이 통과함.
- 2026-08-28: SG5 완료. independent tester PASS—정확한 3→2→1, countdown 중 simulation/input 동결, lifecycle 재진입·stale task 취소, immutable control route, attempt당 단일 RunResult, Main Hub release와 Reduce Motion 계약을 검증했고 focused 59/59 + Feedback integration 4/4, Pro Max/SE Debug build가 통과함.
- 2026-08-29: SG6 독립 tester BLOCKED—iOS 126/126, watchOS 11/11, Debug·Release 네 build, presentation latency, 300초 FPS, runtime 10-cycle memory/release, visual·AX와 protected/resource/provenance/Release 감사까지 통과함. 그러나 Xcode 26.4 CLI는 Simulator app attach를 찾지 못했고 GUI Instruments는 Computer Use AX timeout으로 recording을 시작할 수 없어, 이번 빌드의 exportable continuous `Game Memory` Allocations/VM trace가 없음. SG6는 unchecked로 유지하고 활성 계획을 보존함.
- 2026-08-29: 사용자 요청으로 SG6 Ralph를 재개함. 완료된 회귀·visual·performance 결과는 보존하고, 이번 빌드의 exportable continuous `Game Memory` Allocations/VM trace 확보와 독립 tester 재판정만 다시 수행함.
- 2026-08-29: SG6 완료. Xcode Allocations+VM Tracker 단일 실행 trace를 export해 동일 PID의 10-cycle memory 요약(`pass=true`, baseline 399,605,760B, final 400,572,416B, 115% threshold 이하, last-five 비단조 증가, controller/scene 10/10 해제)을 확인했고 independent tester가 전체 SG6 증거를 재검토해 PASS 판정함.
- 2026-08-29: Ralph 최종 독립 검증 PASS. SG1~SG6와 Final Verification의 회귀·flow·presentation·accessibility·performance·memory·resource 계약을 모두 충족했으며, 실제 iPhone/Apple Watch 검증은 계획대로 비차단 follow-up으로 유지함. 활성 계획을 구현 완료 문서로 archive함.

## Risks

- **Countdown task race:** Retry·Hub·background 뒤 오래된 task가 scene을 unpause할 수 있다. cancellable task, attempt generation token과 explicit stop으로 막는다.
- **Control route drift:** touch-only로 출발한 attempt가 새 Watch packet으로 자동 승격되면 Continue With Touch와 2A의 재시도 의미가 깨진다. immutable session route와 readiness-change test로 잠근다.
- **Foreground deadlock/bypass:** inactive에서 task만 취소하면 복귀 뒤 영구 pause 또는 즉시 주행이 될 수 있다. scene-phase matrix와 idempotent active handler로 같은 attempt의 새 3·2·1을 보장한다.
- **Result 중복 기록:** crashed snapshot이 여러 frame 전달되면 best를 중복 write할 수 있다. running→crashed transition과 attempt별 guard를 함께 둔다.
- **Draft 의미 혼동:** Back이 discard처럼 보일 수 있다. `Pending until Drive` copy와 AX value로 hub에 돌아가도 draft가 유지되지만 저장 전임을 명확히 한다.
- **Watch readiness 불일치:** hub는 Ready인데 router가 touch fallback이면 신뢰가 깨진다. 기존 routing priority와 같은 mapping을 table test로 잠근다.
- **가짜 iPhone calibration:** reference의 Recalibrate/Test Steering를 그대로 구현하면 Watch 권한을 침범한다. iPhone sheet는 설명·live status·Continue Touch만 제공한다.
- **Texture memory:** large hero/background를 app-lifetime cache에 preload하면 기존 21.11MiB baseline이 크게 상승한다. route-lazy presentation loader와 64MiB compiled/runtime gate를 사용한다.
- **Idle GPU cost:** hub/maintenance를 별도 60fps SpriteKit scene으로 만들면 정적 화면에서도 GPU를 소비한다. SwiftUI static PNG composition을 우선한다.
- **Hero identity drift:** presentation hero가 gameplay 차량과 다른 모델처럼 보일 수 있다. 동일 identity sheet, stable pivot와 24-color capture로 감사한다.
- **Short landscape clipping:** mock의 고정 desktop-like 배치는 iPhone SE와 AX Dynamic Type에 맞지 않는다. safe-area-aware adaptive/scrollable control rail과 short-height fallback을 검증한다.
- **Reduce Motion 누락:** SwiftUI transition만 줄이고 SpriteKit shake를 남길 수 있다. scene에 preference를 명시적으로 전달해 world shake도 억제한다.
- **Acceptance 시간 증가:** 모든 Retry에 3초 countdown이 추가된다. soak timeout과 collision trigger는 presentation phase를 인식하도록 갱신한다.

## Open Questions

- None.

## Implementation Result

Implementation completed on 2026-08-29. SG1~SG6와 Final Verification이 independent tester PASS를 받았다. iOS 126/126·watchOS 11/11 full tests, Debug·Release 네 build와 warning 감사, presentation latency, 300초 FPS, exportable single-run Allocations/VM 10-cycle memory, controller/scene 10/10 release, visual·AX, 57.11MiB/max 2048 texture, provenance 27/27 및 protected/resource/Release/dependency 감사가 모두 통과했다. 실제 iPhone/Apple Watch의 VoiceOver gesture, 조향 posture/latency, haptics와 display/battery lifetime은 계획대로 비차단 physical-device follow-up으로 남는다.
