---
title: "프리미엄 PNG 에셋과 차량 차고 커스터마이징"
status: implemented
created: 2026-08-23
updated: 2026-08-25
implemented_at: 2026-08-25
target_repo: "/Users/woohyuk/Desktop/watch-car-racer"
goal_size: large
feature_slug: "premium-assets-garage-customization"
---

# 프리미엄 PNG 에셋과 차량 차고 커스터마이징

## Goal

현재 코드 도형 중심의 자동차·장애물·도로 환경을 독자적인 고품질 PNG 스프라이트 에셋으로 교체하고, 사용자가 매 실행 시 차고에서 차량 3종과 차체 색상 8종을 선택한 뒤 게임을 시작하도록 확장한다. 선택은 기기에 저장되며 Retry에서는 유지되고 차고로 돌아갔을 때만 다시 변경한다.

## Assumptions

- 기존 민트·마젠타·보라 계열의 네온 석양 도로 분위기를 하나의 응집된 프리미엄 테마로 발전시킨다. 여러 맵이나 바이옴 선택은 이번 범위에 포함하지 않는다.
- 차량 3종은 브랜드를 모사하지 않는 랠리 해치, GT 쿠페, 각진 퍼포먼스 카 계열의 서로 구별되는 실루엣으로 제작한다.
- 차량별 주행 성능과 충돌 크기는 동일하다. 차량 선택은 외형만 바꾸며 `GameSimulation`의 결정론, 난이도와 공정성을 변경하지 않는다.
- 완성형 PNG 중심 선택은 차량을 그림자·차체 색상 마스크·고정 디테일 PNG 레이어로 조합하는 방식을 허용한다. 차체를 `SKShapeNode`로 다시 그리지 않으며 24개의 완전 중복 합성 이미지는 만들지 않는다.
- 차고에서 변경 중인 값은 draft이며 `DRIVE`를 누를 때 유효성 확인 후 저장한다. 저장 데이터가 없거나 손상되면 첫 차량과 기본 색상으로 자동 복구한다.
- iOS 18.0, watchOS 11.0, Swift 6, iPhone 전용 가로 화면, SpriteKit/SwiftUI, Watch/touch 조향과 약 60fps 목표를 유지한다.

## Decisions

- 사용자 결정: 자동차·장애물·맵은 완성된 PNG 스프라이트 중심으로 고급화한다.
- 사용자 결정: 차량은 3종, 차체 색상은 8종이며 모두 첫 실행부터 사용할 수 있다.
- 사용자 결정: 앱은 매 프로세스 실행 시 전용 차고 화면으로 시작하고, `DRIVE`를 누르면 게임으로 전환하며 선택값을 로컬에 저장한다.
- 점수, 재화, 잠금, 해금, 결제 없이 모든 조합을 동등하게 제공한다.
- 실제 플레이 중 차량 외형을 바꾸지 않는다. Retry는 같은 차량·색상·seed를 유지하고, 충돌 화면의 `GARAGE`가 현재 run을 종료하고 차고로 돌아가는 명시적 경로가 된다.
- 차량·장애물의 화면 node frame은 충돌 판정에 사용하지 않는다. 기존 월드 좌표 기반 `GameSimulation`이 계속 최종 판정 권한을 가진다.
- 다른 게임이나 자동차 브랜드의 식별 가능한 에셋·실루엣·로고·UI는 복제하지 않고, 모든 PNG의 제작 이력과 권리 상태를 기록한다.

## Scope

- 차량 3종의 고해상도 PNG 레이어 세트와 8색 팔레트, 차고/게임에서 공유하는 차량 sprite factory
- 느린 교통 차량 변형, 도로 방벽, 차선 마크, 아스팔트, 하늘·horizon, 길가 구조물·식생·표지의 원본 PNG 에셋
- Xcode iOS 리소스 빌드 단계, atlas 구성, 텍스처 검증·preload·cache를 담당하는 asset library
- 안정적인 ID를 갖는 차량 catalog, 색상 catalog, 선택 모델과 versioned `UserDefaults` 저장소
- 항상 차고로 시작하는 앱 route, 차량 preview, 차량·색상 선택, loading/disabled 상태가 있는 `DRIVE`
- 충돌 화면의 `RETRY`와 `GARAGE`, route 전환 사이에 유지되는 단일 `PhoneWatchSession`
- PNG asset 계약, 출처·제작 도구·수정·권리·SHA-256을 남기는 provenance 문서
- 자동 테스트, 두 iPhone 크기의 visual QA, 5분 simulator soak와 반복 route 전환 memory/performance 검사

## Out Of Scope

- 차량별 속도·조향·충돌 크기 차이와 성능 밸런싱
- 재화, 점수 기반 해금, 잠금, 미션, 인벤토리, 차량 구매, 광고와 인앱 결제
- 차량 부품 교체, 휠·창문·포인트 색상의 개별 설정, 자유 색상 picker
- 여러 맵·바이옴·날씨·시간대 선택과 절차적 맵 생성
- 온라인 계정, CloudKit 동기화, 서버 저장과 다른 기기 간 설정 동기화
- Watch 앱의 차량 선택 UI와 Watch로 차고를 조작하는 기능
- 주행 중 일시정지 메뉴나 즉시 차량 변경
- 외부 asset pack, 실제 브랜드 차량, 다른 게임의 에셋이나 식별 가능한 디자인 사용
- 이번 기능 때문에 `GameSimulation`의 spawn, collision, score, difficulty 규칙을 변경하는 작업
- 실제 iPhone/Apple Watch의 손목 조향·지연·화면 어두워짐·햅틱 acceptance. 기존 합의대로 후속 실기기 검증으로 남긴다.

## Current Evidence

- `.woohyuk/plan.md`: 새 계획 시작 시 활성 계획이 없었다. 이전 구현 기록은 `docs/2026-08-23-apple-watch-steering-racer/plan.md`에 아카이브되어 있다.
- Git: `main`이 `origin/main`을 추적하고 새 계획 시작 시 작업 트리가 깨끗하다.
- `WatchCarRacer/iOS/App/WatchCarRacerApp.swift`: 앱 시작 즉시 하나의 `GameSessionController`를 만들고 `GameRootView`로 진입하며 app-level route가 없다.
- `WatchCarRacer/iOS/App/GameRootView.swift`: gameplay HUD, touch surface와 충돌 시 `RETRY`만 제공한다. 차고 진입이나 차량 preview가 없다.
- `WatchCarRacer/iOS/App/GameSessionController.swift`: 하나의 `GameScene`과 동일 seed Retry를 소유한다. appearance를 주입하는 계약이나 선택 저장소가 없다.
- `WatchCarRacer/iOS/Game/GameScene.swift`: player car, traffic car, barrier, roadside props, road, lane, sun을 `SKShapeNode`와 hard-coded `UIColor`로 생성한다.
- `WatchCarRacer/iOS/Game/GameSimulation.swift`: Foundation-only 결정론적 모델이며 player/obstacle 충돌을 월드 좌표로 판정한다. 시각 교체와 독립된 올바른 경계이다.
- `WatchCarRacer/iOS/Game/RoadProjection.swift`: node frame과 무관하게 거리 기반 위치·scale을 계산하므로 PNG sprite도 동일 투영을 재사용할 수 있다.
- `WatchCarRacer.xcodeproj/project.pbxproj`: 네 target의 Resources build phase가 비어 있고 iOS asset catalog/atlas membership이 없다.
- 저장소 전체에서 `UserDefaults`, `AppStorage`, 차량 catalog, customization 또는 garage route 구현이 발견되지 않았다.
- 기존 기준선은 iOS 50개와 watchOS 11개 테스트, iOS/watchOS Release build, 독립 310초 simulator soak 평균 59.9fps·최저 53fps이다.

## Architecture

### Selection And Flow Contracts

- `VehicleID`: 정확히 세 개의 안정적인 raw-value ID
- `VehicleColorID`: 정확히 여덟 개의 안정적인 raw-value ID
- `VehicleSelection`: `vehicleID`와 `colorID`를 담는 `Codable`, `Equatable`, `Sendable` 값
- `VehicleCatalog`: 표시 이름, 접근성 이름, PNG layer 이름, 논리 render 크기와 normalized pivot을 제공하는 정적 catalog
- `VehicleAppearance`: catalog와 selection에서 검증·해결된 불변 run 단위 렌더 값
- `VehicleSelectionStoring`: 저장 seam과 versioned `UserDefaults` 구현
- `AppFlowController`: `.garage`와 `.playing` route, 차고 draft, asset readiness, 현재 `GameSessionController`의 생성·폐기를 관리

앱이 시작되면 app-owned `PhoneWatchSession`, selection store, shared `GameAssetLibrary`, `AppFlowController`를 한 번 만든다. route는 저장값과 무관하게 항상 `.garage`에서 시작한다. `DRIVE`는 asset preload와 selection 검증이 끝난 경우에만 draft를 저장하고 새 `GameSessionController`를 만든다. Retry는 기존 controller·scene·seed·appearance를 유지하고, `GARAGE`만 controller를 폐기한 뒤 차고로 돌아간다. route 전환은 `PhoneWatchSession`을 재생성하거나 Watch 연결을 다시 활성화하지 않는다.

### PNG Asset Contract

```text
WatchCarRacer/iOS/Resources/
  Vehicles.atlas/
    rally_shadow.png
    rally_paint.png
    rally_details.png
    gt_shadow.png
    gt_paint.png
    gt_details.png
    angular_shadow.png
    angular_paint.png
    angular_details.png
  Obstacles.atlas/
    barrier_*.png
    traffic_*.png
  Environment.atlas/
    lane_*.png
    roadside_*.png
    road_decal_*.png
  Backgrounds/
    sky_horizon.png
    asphalt.png
  AssetManifest.json
docs/assets/provenance.md
Scripts/measure_compiled_texture_memory.swift
```

- 차량 layer는 384×576px canvas, 8-bit sRGB RGBA PNG로 고정하고 같은 pivot을 사용한다. 진행 방향은 `+Y`, anchor는 collision center `(0.5, 0.5)`이다. traffic은 320×480px, barrier는 512×256px, lane은 64×256px, sky는 2048×1024px, asphalt는 1024×1024px로 고정하고, 512×512px 이내의 roadside/decal 정확한 크기는 `AssetManifest.json`에 잠근다.
- roadside prop은 bottom-center `(0.5, 0)`, 장애물은 collision center를 anchor로 사용한다.
- 색상은 white-alpha `paint` PNG만 `SKSpriteNode.color`와 `colorBlendFactor = 1`로 tint한다. 유리·휠·trim·광원·highlight는 `details`, 그림자는 `shadow`에 유지한다.
- 차량 source canvas는 garage 확대 preview에도 견디도록 같은 비율의 RGBA 원본을 사용하고, gameplay에서는 명시적 point size로 축소한다. raw pixel 크기를 충돌 또는 game scale로 사용하지 않는다.
- `GameAssetLibrary`가 atlas preload, texture lookup, linear filtering, cache와 누락된 texture 보고를 단독 소유한다. Garage 표시 중 차량/preview asset을 먼저, obstacle/environment를 이어 preload하며 gameplay asset 준비 전 `DRIVE`는 loading 상태로 비활성화한다.
- atlas source/compiled page는 2048×2048 이하로 제한하고 전체 decoded texture allocation은 64MiB 이하로 제한한다. build된 `.app`의 compiled atlas page와 standalone background를 `Scripts/measure_compiled_texture_memory.swift`가 ImageIO로 열어 page별 `pixelWidth × pixelHeight × 4`를 합산하며 packing/padding을 포함한다. ImageIO로 읽을 수 없는 GPU 전용 page가 생기면 preload/render 전후 Metal allocated-size delta를 함께 기록하고 둘 중 큰 값을 gate로 사용한다. texture는 node마다 복제하지 않고 shared reference를 사용한다.
- `docs/assets/provenance.md`에는 asset family별 creator/tool, 생성일, prompt 또는 source material, 수정 내용, 권리·license 상태와 SHA-256을 기록한다.

### Rendering Boundary

- `GameSimulation.swift`와 `RoadProjection.swift`의 production 규칙은 변경하지 않는다.
- `VehicleSpriteNode`는 차고 preview와 gameplay player가 함께 사용하는 layered sprite factory이다.
- player는 선택된 `VehicleAppearance`로 생성한다. 세 차량 모두 기존 player world width/length를 공유한다.
- traffic sprite variant는 `obstacle.id % variantCount`처럼 기존 ID로 안정적으로 선택하며 simulation RNG 호출이나 obstacle kind를 추가하지 않는다.
- barrier, traffic car, lane mark와 roadside prop은 PNG node로 교체하되 기존 거리·scale·parallax·z-order 계산을 유지한다.
- projected trapezoid road는 구조 geometry로 남기고 authored asphalt texture와 road decal을 입힌다. sky/horizon/sun은 응집된 backdrop layer로 교체한다.
- near-miss flash, score pop, collision shake·particle 같은 순간 feedback은 코드 생성 방식을 유지할 수 있다.

### Expected Files

- `WatchCarRacer/iOS/Customization/VehicleCatalog.swift`
- `WatchCarRacer/iOS/Customization/VehicleSelectionStore.swift`
- `WatchCarRacer/iOS/App/AppFlowController.swift`
- `WatchCarRacer/iOS/App/AppRootView.swift`
- `WatchCarRacer/iOS/App/GarageView.swift`
- `WatchCarRacer/iOS/Game/GameAssetLibrary.swift`
- `WatchCarRacer/iOS/Game/VehicleSpriteNode.swift`
- `WatchCarRacer/iOS/Resources/`
- `WatchCarRacer/iOS/Resources/AssetManifest.json`
- `WatchCarRacerTests/VehicleCatalogTests.swift`
- `WatchCarRacerTests/VehicleSelectionStoreTests.swift`
- `WatchCarRacerTests/AppFlowControllerTests.swift`
- `WatchCarRacerTests/GameAssetLibraryTests.swift`
- `docs/assets/provenance.md`
- `Scripts/measure_compiled_texture_memory.swift`
- 기존 `WatchCarRacerApp.swift`, `GameRootView.swift`, `GameSessionController.swift`, `GameScene.swift`, `project.pbxproj`

## Subgoals

- [x] SG1: 원본 PNG 아트 계약과 iOS resource pipeline 구성
  - Outcome: 차량·장애물·환경 PNG가 잠긴 canvas/pivot/naming 규칙과 provenance를 갖고 iOS bundle에서 preload·조회되며, 누락된 texture가 조용히 빈 node로 렌더링되지 않는다.
  - Work: `VehicleCatalog.swift`의 asset-facing 기반인 세 `VehicleID`, vehicle display/accessibility name, layer texture name, logical render size와 pivot descriptor를 먼저 만든다. `WatchCarRacer/iOS/Resources/`에 Vehicles/Obstacles/Environment atlas, Backgrounds와 `AssetManifest.json`을 만들고 세 차량의 shadow/paint/details layer, traffic 변형, barrier, lane, road·sky, roadside kit을 추가한다. `docs/assets/provenance.md`, `GameAssetLibrary.swift`, `Scripts/measure_compiled_texture_memory.swift`, iOS-only Xcode resource membership을 구성한다. 첫 차량 art sheet의 perspective·canvas·anchor를 기준으로 나머지를 정규화하고 Watch target에는 이 리소스를 넣지 않는다.
  - Verify:
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' build`
    - bundle-backed `GameAssetLibraryTests`에서 SG1의 asset descriptor와 `AssetManifest.json`이 선언한 모든 texture가 nonzero size로 resolve되고, vehicle layer canvas·8-bit sRGB RGBA·anchor 계약과 각 family의 잠긴 pixel 크기를 검사한다.
    - build된 `.app`에 `Scripts/measure_compiled_texture_memory.swift`를 실행해 compiled atlas page와 standalone background의 packing/padding 포함 decoded allocation이 64MiB 이하이고 어떤 page도 2048×2048을 넘지 않는지 검사한다. GPU 전용 format이면 preload/render 전후 Metal allocation delta와 비교해 큰 값을 사용한다.
    - provenance의 SHA-256이 실제 production PNG와 일치해야 한다.
    - 투명 edge halo, 잘린 그림자, perspective·광원 불일치를 첫 차량·traffic·barrier·roadside 대표 sheet에서 수동 확인한다.
  - Depends on: None

- [x] SG2: 차량 3종·색상 8종 catalog와 안전한 로컬 저장 구현
  - Outcome: 정확히 24개 조합이 모두 유효하며 마지막으로 `DRIVE`한 선택이 다음 실행 차고에 복원되고, 손상되거나 미래 version인 데이터는 유효한 기본값으로 자동 복구된다.
  - Work: SG1의 `VehicleCatalog.swift`에 여덟 stable color ID/이름/RGBA와 유효 조합 resolution을 추가하고 `VehicleSelectionStore.swift`와 테스트를 만든다. `VehicleSelection`, `VehicleAppearance`, storage protocol, versioned `UserDefaults` adapter를 구현한다. 차량은 시각 descriptor만 가지며 gameplay stat을 갖지 않는다.
  - Verify:
    - `VehicleCatalogTests`에서 3개 차량, 8개 색상, 24개 조합의 유일성·완전성, texture name과 논리 크기·pivot의 유효성을 검사한다.
    - `VehicleSelectionStoreTests`에서 save/load round trip, 빈 저장소, 손상 JSON, unknown ID, unsupported version, default self-heal을 fake store/suite로 검사한다.
    - 저장·복원 전후 `GameSimulation`의 seed 기반 snapshot/event sequence가 기존 결과와 동일해야 한다.
  - Depends on: SG1

- [x] SG3: 선택 차량과 PNG 자동차·장애물을 게임 renderer에 통합
  - Outcome: 선택한 차량 body/color가 주행 화면에 표시되고 traffic/barrier도 원본 PNG로 렌더링되며, Retry 이후에도 appearance와 기존 collision·near-miss 결과가 변하지 않는다.
  - Work: `VehicleSpriteNode.swift`를 추가하고 `GameSessionController`가 불변 `VehicleAppearance`와 shared `GameAssetLibrary`를 `GameScene`에 주입하게 한다. `GameScene.buildPlayerCar`와 obstacle shape builder를 sprite factory로 교체한다. traffic variant는 obstacle ID로 안정적으로 고르고 기존 world size, projection, feedback node와 event 흐름을 유지한다.
  - Verify:
    - controller/scene seam 테스트에서 24개 selection이 올바른 texture layer와 tint로 resolve되고 Retry가 appearance·seed를 유지한다.
    - 같은 seed/input의 `GameSimulationTests` snapshot/event sequence, collision/near-miss, projection, input router와 feedback 전체 회귀 테스트가 그대로 통과한다.
    - `git diff --exit-code d1b2e69 -- WatchCarRacer/iOS/Game/GameSimulation.swift WatchCarRacer/iOS/Game/RoadProjection.swift`로 simulation/projection production 파일이 기준 커밋에서 변경되지 않았음을 확인한다.
    - representative 3차량×8색 gameplay capture에서 잘못된 tint, layer offset, anchor drift가 없고 obstacle sprite와 collision 위치가 시각적으로 오해를 만들지 않는다.
  - Depends on: SG1, SG2

- [x] SG4: 매 실행 차고 진입과 DRIVE·RETRY·GARAGE route 완성
  - Outcome: 앱은 항상 전용 차고로 열리고, 사용자는 접근 가능한 UI로 차량 3종과 색상 8종을 고른 뒤 asset 준비가 끝나면 `DRIVE`할 수 있다. Retry는 같은 run을 유지하고 `GARAGE`는 run을 종료해 선택 화면으로 돌아간다.
  - Work: `AppFlowController.swift`, `AppRootView.swift`, `GarageView.swift`와 preview를 추가하고 `WatchCarRacerApp.swift`가 app-owned Watch session/store/asset library/flow를 한 번만 만들게 한다. `GameRootView` crash overlay에 `GARAGE`를 추가한다. 차고 draft와 committed selection을 분리하고 route 전환 중 중복 controller 생성이나 Watch session 재활성화를 막는다.
  - Verify:
    - `AppFlowControllerTests`에서 cold launch→garage, saved selection→draft, Drive 1회 저장/한 controller 생성, loading 중 Drive 차단, Retry route 불변, Garage controller 폐기, 다음 Drive 새 appearance를 검사한다.
    - 앱 강제 종료·재실행 후에도 차고로 시작하면서 마지막 committed selection이 표시되어야 한다.
    - 세 차량 버튼과 44×44pt 이상 여덟 swatch에 이름·selected trait·checkmark/outline이 있어 색만으로 상태를 전달하지 않는지 VoiceOver로 확인한다.
    - iPhone 17 Pro Max iOS 26.4와 설치된 `iPhone SE (3rd generation),OS=26.0`의 양쪽 landscape, 가장 큰 Dynamic Type, Reduce Motion에서 preview·controls·DRIVE가 잘리거나 겹치지 않아야 한다.
  - Depends on: SG2, SG3

- [x] SG5: 네온 석양 expressway 맵 kit을 PNG 중심으로 고급화
  - Outcome: sky/horizon, road texture와 detail, lane, roadside props가 하나의 독자적인 고품질 테마로 통합되고 속도감·가독성을 유지하며 gameplay geometry와 충돌 규칙은 변하지 않는다.
  - Work: `GameScene`의 shape-built sky/sun/horizon treatment, lane block, 세 roadside prop 스타일을 Backgrounds/Environment sprite로 교체하고 projected road에 asphalt texture/decal을 적용한다. 기존 road trapezoid, `RoadProjection`, parallax base distance, depth scale, z-order와 effect 코드는 유지한다.
  - Verify:
    - 기존 `RoadProjectionTests`와 전체 `GameSimulationTests`가 수정 없이 통과한다.
    - `git diff --exit-code d1b2e69 -- WatchCarRacer/iOS/Game/GameSimulation.swift WatchCarRacer/iOS/Game/RoadProjection.swift`로 simulation/projection production 파일이 기준 커밋에서 변경되지 않았음을 확인한다.
    - 두 iPhone 크기와 양쪽 landscape에서 horizon seam, road stretch, lane depth, roadside pop-in, alpha halo와 차량/장애물 대비를 확인한다.
    - 정지·기본 속도·최대 난이도에서 도로 흐름과 장애물 판독성이 유지되고 near-miss·collision feedback이 배경에 묻히지 않아야 한다.
    - 차량·장애물·맵·UI가 특정 참고 게임이나 실제 브랜드를 직접 모사하지 않는지 provenance와 screenshot으로 수동 감사한다.
  - Depends on: SG1, SG3

- [x] SG6: 전체 regression·visual·memory·performance acceptance
  - Outcome: 새 PNG와 차고 흐름이 기존 Watch/touch 게임을 회귀시키지 않고 반복 route 전환과 5분 주행에서도 약 60fps와 안정된 memory를 유지한다.
  - Work: 발견된 결함만 해당 모듈에서 수정하고 새 기능을 추가하지 않는다. DEBUG asset/readiness 진단과 재현 가능한 visual QA evidence를 정리한다.
  - Verify:
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' test`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' test`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -configuration Debug -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' build`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -configuration Release -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' build`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -configuration Debug -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' build`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -configuration Release -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' build`
    - 네 build가 Swift/Clang warning 없이 통과하고 iOS resource가 Watch bundle에 중복되지 않아야 한다.
    - `git diff --exit-code d1b2e69 -- WatchCarRacer/iOS/Game/GameSimulation.swift WatchCarRacer/iOS/Game/RoadProjection.swift`로 simulation/projection production 파일 불변성을 최종 확인한다.
    - cold launch→garage→24개 조합 preview→Drive→touch/Watch fallback→near miss→collision→Retry→collision→Garage→다른 차량 Drive의 전체 흐름을 확인한다.
    - iPhone 17 Pro Max simulator에서 5분 연속 주행 평균 58fps 이상이고, 1초 간격 DEBUG 표본이 2회 연속 50fps 미만인 구간·첫 obstacle spawn texture hitch·앱 정지·상태 손상이 없어야 한다.
    - 한 연속 Instruments Allocations/VM trace에서 preload 완료→Drive→collision→Garage 1회 warm-up 후 Garage에서 10초 idle한 RSS를 baseline으로 기록한다. 이후 동일 route cycle을 10회 반복하고 각 Garage 복귀 5초 후 RSS를 기록하며, 마지막 복귀 10초 idle 값이 baseline의 115% 이하이고 마지막 다섯 표본이 계속 증가하지 않아야 한다.
    - 모든 production PNG가 provenance에 있고 실제 SHA-256과 일치하며 외부 asset, 브랜드 logo, 금지된 서비스·capability·새 runtime dependency가 없어야 한다.
  - Depends on: SG1, SG2, SG3, SG4, SG5

## Final Verification

- SG6에 명시한 iOS 전체 테스트, watchOS 전체 테스트와 네 Debug·Release simulator build command가 모두 통과한다.
- 앱을 종료하고 다시 실행할 때마다 차고로 시작하며 마지막 `DRIVE` 선택이 복원되고, 3차량×8색 24개 조합을 모두 선택·preview·주행할 수 있다.
- `DRIVE` 전에는 draft만 바뀌고, Drive 이후 Retry는 같은 appearance/seed를 유지하며 `GARAGE` 뒤 다음 Drive는 새 appearance로 새 run을 만든다.
- 모든 차량·traffic·barrier·lane·road·sky/horizon·roadside primary art가 PNG texture로 렌더링되고 누락 texture, layer offset, alpha halo, anchor drift가 없다.
- 차량 외형에 따라 결정론적 spawn, collision, near-miss, score, difficulty 또는 Watch/touch 입력 결과가 바뀌지 않는다.
- 설치된 `iPhone SE (3rd generation),OS=26.0`와 iPhone 17 Pro Max iOS 26.4의 양쪽 landscape, 최대 Dynamic Type, Reduce Motion과 VoiceOver에서 차고의 차량·색상·DRIVE가 사용 가능하고 색만으로 선택 상태를 전달하지 않는다.
- 5분 simulator run이 평균 58fps 이상이고 1초 표본 2회 연속 50fps 미만·texture hitch·freeze가 없다. 정해진 warm-up/baseline 절차 뒤 10회 garage/game 전환의 마지막 RSS가 baseline의 115% 이하이고 마지막 다섯 표본이 계속 증가하지 않는다.
- compiled atlas page와 standalone background를 포함한 실제 decoded allocation 64MiB budget, 2048×2048 page cap, iOS-only target membership, provenance SHA-256, 독창성과 금지 기능·의존성 부재를 확인한다.
- 실제 iPhone/Apple Watch의 자세·지연·수명·햅틱은 이번 완료를 차단하지 않으며 기존 후속 실기기 검증 목록에 남긴다.

## Progress

- 2026-08-24: Ralph 실행을 시작했다. SG1부터 단일 구현자와 독립 테스터를 순차 실행한다.
- 2026-08-24: SG1 PASS — 19개 원본 PNG, asset descriptor/library/manifest/provenance와 iOS-only resource pipeline을 구성했다. 독립 테스트 6개, compiled texture 21.11MiB, SHA-256 19/19, 전체 시각 검사를 통과했다.
- 2026-08-24: SG2 PASS — 차량 3종 × 색상 8종의 24개 외형과 버전 1 단일-key 저장소를 구성했다. 독립 집중 테스트 11개, 전체 iOS 테스트 67개, 결정성 테스트 10개 및 시뮬레이터 빌드를 통과했고 손상·미지 ID·미래 버전 self-heal을 확인했다.
- 2026-08-24: SG3 PASS — 선택 appearance와 shared asset library를 controller→scene에 고정 주입하고 차량 3-layer paint-only tint 및 ID 기반 traffic/barrier PNG renderer를 연결했다. 독립 집중 테스트 34개, 전체 iOS 테스트 70개와 시뮬레이터 빌드·기준 파일 불변 검사를 통과했다.
- 2026-08-24: SG4 PASS (attempt 2) — cold launch 차고, draft/commit, DRIVE·RETRY·GARAGE controller 수명과 접근 가능한 3×8 선택 UI를 연결했다. 실제 atlas를 Vehicles→Obstacles→Environment 순서로 직렬 preload하도록 보완한 뒤 독립 집중 테스트 23개, 전체 iOS 테스트 80개, 두 기기 빌드와 5회 반복 launch를 통과했다.
- 2026-08-24: SG5 PASS — sky·asphalt·lane·roadside·chevron을 PNG 기반 네온 석양 맵으로 통합하면서 기존 road/projection·parallax 공식을 유지했다. 독립 전체 iOS 테스트 85개, 두 기기 빌드, provenance 19/19 및 실제 양쪽 landscape(orientation 3/4) crash gameplay 시각 검증을 통과했다.
- 2026-08-25: SG6 검증을 재개했다. 사용자가 macOS Developer Tools Security를 활성화했으며, 유효한 연속 Instruments Allocations/VM trace와 독립 전체 회귀 검증을 다시 수행한다.
- 2026-08-25: SG6 재검증에서 iOS 87개와 watchOS 11개 전체 테스트, 네 Debug·Release 빌드, 21.11MiB/max 2048 texture budget, provenance 19/19, Watch 리소스 격리와 기준 파일 불변 검사가 통과했다. Instruments는 Xcode 최초 실행 구성요소가 미완료여서 `xcodebuild -checkFirstLaunchStatus`가 69를 반환하며, 사용자의 `sudo xcodebuild -runFirstLaunch` 완료를 기다린다.
- 2026-08-25: SG6 PASS (attempt 2) — 유효한 단일 192.679초 Instruments Allocations/VM trace에서 final RSS 356,286,464 bytes가 baseline 355,565,568 bytes의 115% 이내였고 마지막 다섯 표본의 연속 증가가 없으며 controller 10/10 해제를 확인했다. 독립 테스트에서 iOS 87/87, watchOS 11/11, 네 빌드, FPS 300표본 평균 59.932/min 58, 24/24 preview와 AX 매핑, Reduce Motion 실제 ON 흐름, provenance 19/19와 Watch 리소스 격리가 모두 통과했다. Apple 공식 제한상 Simulator에서 불가능한 실제 VoiceOver 조작은 사용자가 유예한 실기기 검증 목록에 남긴다.
- 2026-08-25: Final Verification PASS — fresh 독립 테스터가 SG1–SG6 누적 구현, iOS 87/87와 watchOS 11/11 전체 테스트, loading gate 20/20, 네 Debug·Release 빌드, 24개 실제 preview, 저장·Retry·Garage 흐름, AX·Reduce Motion, PNG/provenance/Watch 격리, FPS와 단일 Instruments trace를 재검증했다. 구현 실패나 비실기기 blocker는 발견되지 않았다.

## Risks

- **PNG perspective drift:** 차량·traffic·장애물의 카메라 각도와 광원이 다르면 한 장면처럼 보이지 않는다. 첫 art sheet에서 canvas, 진행 방향, pivot, 광원을 잠그고 전 asset을 같은 계약으로 정규화한다.
- **Tint 품질 저하:** 완성 이미지를 통째로 tint하면 명암과 유리가 무너진다. white-alpha paint mask만 tint하고 authored details와 shadow를 분리한다.
- **충돌 시각 불일치:** 서로 다른 silhouette가 같은 world collision box를 쓰므로 과도한 투명 여백은 부당하게 느껴질 수 있다. 동일 logical footprint 안에서 body를 설계하고 frame 기반 충돌을 금지한다.
- **Texture memory와 첫 프레임 hitch:** 큰 PNG와 atlas preload가 기존 59.9fps 기준선을 악화시킬 수 있다. 2048 page/64MiB budget, shared cache, Garage preload와 disabled Drive로 통제한다.
- **Route별 객체 누수:** controller/scene을 반복 생성하면서 node graph가 보존되면 memory가 누적될 수 있다. app-owned asset/session과 run-owned controller를 분리하고 10회 전환 trace로 확인한다.
- **저장 schema 변화:** raw ID 변경이나 손상 데이터가 차고를 막을 수 있다. versioned payload, catalog validation, default self-heal을 적용한다.
- **짧은 landscape 높이와 접근성:** garage preview와 24개 control이 Dynamic Type에서 충돌할 수 있다. 적응형·scrollable control column과 native SwiftUI button/selection trait를 사용한다.
- **원본성·권리:** 생성 또는 제작한 art가 참고작·브랜드와 유사하거나 출처가 불명확할 수 있다. provenance, SHA-256과 screenshot originality audit 없이는 SG1/SG6을 통과시키지 않는다.

## Open Questions

- None. 구현에 영향을 주는 에셋 방식, 차량·색상 범위와 진입 흐름은 사용자 결정으로 확정했다.

## Implementation Result

Implemented on 2026-08-25.

### Summary

- 독자적인 네온 석양 PNG art kit으로 차량, traffic, barrier, sky, asphalt, lane과 roadside primary art를 고급화했다.
- 매 실행 차고에서 차량 3종과 색상 8종을 선택하고 `DRIVE`로 확정하며, Retry에서는 appearance와 seed를 유지하고 `GARAGE` 이후 새 run을 시작하는 흐름을 완성했다.
- iOS-only preload/cache, versioned selection persistence/self-heal, 접근 가능한 선택 상태, DEBUG-only FPS·memory acceptance 진단을 추가했다.

### Completed Subgoals

- SG1: 19개 production PNG, manifest, provenance와 iOS-only resource pipeline.
- SG2: 3차량×8색 catalog와 versioned selection store.
- SG3: 3-layer vehicle tint renderer와 ID 기반 traffic/barrier renderer.
- SG4: cold-launch garage, draft/commit, Drive/Retry/Garage route와 serial atlas preload.
- SG5: PNG 기반 sky/asphalt/lane/roadside neon expressway map.
- SG6: 전체 regression, visual/accessibility, texture, FPS와 memory acceptance.

### Changed Files

- App flow/UI: `AppFlowController.swift`, `AppRootView.swift`, `GarageView.swift`, `WatchCarRacerApp.swift`, `GameRootView.swift`.
- Customization/rendering: `VehicleCatalog.swift`, `VehicleSelectionStore.swift`, `GameAssetLibrary.swift`, `VehicleSpriteNode.swift`, `GameScene.swift`, `GameSessionController.swift`.
- Assets/tooling: `WatchCarRacer/iOS/Resources/`, `docs/assets/provenance.md`, `Scripts/measure_compiled_texture_memory.swift`, Xcode project resource membership.
- Acceptance/tests: `SG6AcceptanceCoordinator.swift`와 catalog/store/flow/renderer/map/session XCTest suites.

### Verification

- Fresh final iOS tests 87/87, watchOS tests 11/11, loading gate 20/20; iOS/watchOS Debug·Release 네 빌드가 Swift/Clang warning 없이 통과했다. AppIntents framework 미사용 metadata-skip note만 별도로 확인했다.
- 24/24 차량·색상 preview, persisted committed selection, Drive→collision→Retry/Garage→relaunch 흐름과 Simulator AX semantics/Reduce Motion ON을 확인했다.
- production provenance SHA-256 19/19, compiled texture 22,135,400 bytes(21.11MiB), max 2048, Watch bundle 금지 iOS resource 0을 확인했다.
- FPS 첫 300표본은 평균 59.932, 최소 58, 연속 2회 50 미만 0이었다.
- 단일 192.679207초 Instruments Allocations/VM trace에서 baseline 355,565,568 bytes, final 356,286,464 bytes(115% threshold 408,900,403 이내), 마지막 다섯 표본 연속 증가 없음, controller 10/10 해제를 확인했다.
- `GameSimulation.swift`와 `RoadProjection.swift`는 기준 `d1b2e69`에서 변경되지 않았고, 금지 dependency·capability·브랜드 logo·잔존 acceptance process가 없었다.

### Follow-ups

- 실제 iPhone/Apple Watch에서 손목 자세, 조향 지연, 화면·배터리 수명과 햅틱을 검증한다.
- Apple 공식 제한상 Simulator에서 제공되지 않는 실제 VoiceOver gesture-only task completion을 실물 iPhone에서 검증한다. Simulator AX label/value/selected trait, 44pt 이상 control과 색상 외 선택 표시는 이번 완료에서 검증했다.
