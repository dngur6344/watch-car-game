---
title: "Apple Watch 가상 운전대 레이싱 MVP"
status: implemented
created: 2026-08-19
updated: 2026-08-23
implemented_at: 2026-08-23
target_repo: "/Users/woohyuk/Desktop/watch-car-racer"
goal_size: large
feature_slug: "apple-watch-steering-racer"
---

# Apple Watch 가상 운전대 레이싱 MVP

## Goal

Apple Watch를 손목형 가상 운전대로 사용해 iPhone의 차량을 조향하고, 장애물과 느린 차량을 피하면서 속도와 점수를 높이는 박진감 있는 세로 슬라이스 게임을 만든다. 그래픽은 친근한 2.5D 로우폴리·복셀 감성을 사용하되, 캐릭터·차량·색상·UI·에셋은 모두 독자적으로 설계한다.

성공한 MVP는 Watch 실기기 조향과 터치 대체 조향으로 한 판을 시작하고, 피하고, 충돌하고, 즉시 재시작할 수 있어야 한다. Watch 입력이 끊겨도 마지막 조향값이 고정되지 않아야 하며, iPhone 게임은 계속 플레이할 수 있어야 한다.

## Assumptions

- 최소 지원 버전은 iOS 18.0과 watchOS 11.0이며 Swift 6 언어 모드를 사용한다. 현재 로컬 검증 SDK는 iOS/watchOS 26.4이므로 이전 OS 호환성은 해당 런타임 또는 실기기를 확보했을 때 별도로 확인한다.
- iPhone 앱은 iPhone 전용이며 좌·우 가로 방향만 지원한다. iPhone은 손에 들고 기울이는 입력 장치가 아니라 앞에 놓거나 거치한 게임 화면으로 간주한다.
- 차량은 자동 전진하고 사용자는 좌우 조향만 담당한다. 한 번 충돌하면 주행이 종료되는 짧은 무한 주행 방식이며, 점수 저장·리더보드는 이번 MVP에 포함하지 않는다.
- Watch 중립 자세는 팔을 편안하게 앞으로 둔 상태에서 Watch 화면이 위를 향하는 자세로 시작한다. 실제 조향 축, 부호, 약 3도 데드존과 약 30도 풀록 범위는 SG2 실기기 검증 결과로 확정한다.
- 좌우 손목 및 Digital Crown 방향을 모두 지원하는 것을 목표로 하되, 부호 매핑은 실제 지원 조합별로 SG2에서 검증한다.
- Watch 연결이 끊기면 게임을 자동 일시정지하지 않고 조향을 100~150ms 동안 중립으로 감쇠한 뒤 화면 터치 조향으로 자연스럽게 전환한다.
- Watch 앱의 일반적인 전면 실행 범위만 사용한다. 게임과 무관한 운동 세션, HealthKit, 백그라운드 모드 또는 부적절한 extended runtime entitlement로 실행 시간을 늘리지 않는다.
- 1차 그래픽은 SpriteKit 코드로 조합한 단순 도형과 독자 팔레트를 사용한다. 앱 아이콘과 사운드처럼 파일이 필요한 에셋은 직접 제작하거나 사용 권한이 명확한 원본만 저장소에 추가한다.

## Decisions

- 1차 기기 범위는 iPhone과 해당 iPhone에 페어링된 Apple Watch이다.
- iPad 직접 플레이 및 iPhone을 통한 iPad 중계는 이번 계획에서 제외한다.
- 구현 스택은 SwiftUI 셸 + iPhone SpriteKit 2.5D 게임 + watchOS Core Motion/WatchConnectivity이다. Unity, SceneKit, RealityKit 및 실제 3D 물리는 사용하지 않는다.
- Watch가 없거나 연결이 끊긴 경우 iPhone 하단 수평 드래그 방식의 터치 조향을 제공한다.
- Watch는 얇은 입력 장치로 유지하고, 입력 선택·게임 시뮬레이션·충돌·점수·렌더링의 최종 권한은 iPhone에 둔다.
- 사용자 요청에 따라 별도 계획/코드 리뷰어 검토는 실행하지 않는다. 읽기 전용 아키텍트의 설계 결과만 이 계획에 반영했다.
- 2026-08-20 사용자 결정에 따라 실제 iPhone/Apple Watch 조향 검증은 구현 subgoal의 진행 차단 조건에서 제외하고 최종 검증으로 이관한다. 모든 subgoal은 자동 테스트와 시뮬레이터 증거를 기준으로 계속 진행한다.
- 2026-08-23 사용자 결정에 따라 현재 확보할 수 없는 실제 iPhone/Apple Watch acceptance는 구현 완료와 아카이브의 차단 조건에서 제외하고 명시적 후속 검증으로 보존한다. 현재 완료 판정은 자동 테스트와 시뮬레이터 acceptance에 한정한다.

## Scope

- `WatchCarRacer` iPhone 앱, `WatchCarRacerWatchApp` 동반 Watch 앱, iOS/watchOS 단위 테스트 타깃으로 구성된 새 Xcode 프로젝트
- Watch 중립 보정, Core Motion 샘플링, 정규화·필터링된 `-1...1` 조향값, WatchConnectivity 실시간 전송
- 최신 유효 입력을 고르는 iPhone 입력 라우터와 연결 끊김·오래된 패킷·재연결 처리
- 터치 드래그 조향 및 손을 떼면 중앙으로 복귀하는 동작
- 자동 전진, 연속 좌우 이동, 속도/스폰 난이도 상승, 점수, 근접 회피 보너스, 한 번의 충돌과 즉시 재시작
- 한 차선을 막는 도로 장애물과 다른 상대 속도로 접근하는 느린 차량, 총 두 종류의 장애물
- 원근 투영된 사다리꼴 도로, 흐르는 차선, 블록형 차량·장애물, 길가 패럴랙스, 독자 색상과 UI
- 근접 회피 및 충돌 시 화면 펀치·플래시·흔들림·파티클·iPhone 햅틱·best-effort Watch 햅틱·간단한 원본 사운드
- 시뮬레이터 기반 빌드/단위 테스트와 페어링된 iPhone/Watch 실기기 지연·수명·조향 검증

## Out Of Scope

- iPad, iPad relay, Android, macOS 및 Apple TV
- 멀티플레이, 계정, CloudKit, Game Center, 온라인/로컬 리더보드, 영구 진행 저장
- 광고, 결제, 인앱 구매, 분석 SDK 및 외부 서버
- 파워업, 체력, 미션, 인벤토리, 차량 수집, 바이옴 시스템, AI 차선 변경
- HealthKit, 운동 세션, 앱 목적과 맞지 않는 extended runtime 또는 백그라운드 권한
- 타사 게임 엔진과 타사 런타임 의존성
- 다른 게임의 에셋, 캐릭터 실루엣, 차량 디자인, 팔레트, UI 또는 사운드 복제

## Current Evidence

- 저장소 루트: 현재 파일과 Git 메타데이터가 없는 빈 디렉터리이므로 기존 코드·설정·사용자 변경과의 충돌은 없다.
- `.woohyuk/plan.md`: 계획 시작 전 활성 계획이 존재하지 않았다.
- 로컬 도구: Xcode 26.4 (`17E192`), Swift 6.3, iOS/watchOS 26.4 SDK를 사용할 수 있다.
- 로컬 시뮬레이터: iPhone 17 Pro Max (iOS 26.4)와 Apple Watch Series 11 46mm (watchOS 26.4) 페어를 사용할 수 있다.
- [Apple Watch 설정 문서](https://support.apple.com/en-lamr/guide/watch/apdde4d6f98e/watchos): Apple Watch는 iPhone과 페어링하여 사용하므로 iPad 직접 제어 경로를 전제로 할 수 없다.
- [Watch Connectivity](https://developer.apple.com/documentation/WatchConnectivity): Watch 앱과 페어링된 iOS 동반 앱 사이의 통신 프레임워크이다.
- [WCSession](https://developer.apple.com/documentation/watchconnectivity/wcsession): 즉시 메시지는 상대 앱의 reachability가 필요하며, 백그라운드 전송 API는 실시간 조향에 적합하지 않다.
- [Core Motion](https://developer.apple.com/documentation/coremotion/): watchOS 기기의 자세와 회전 데이터를 게임 입력으로 사용할 수 있다.
- [SpriteKit](https://developer.apple.com/documentation/spritekit): iOS에서 고성능 2D 장면·애니메이션·파티클을 렌더링할 수 있다.
- 아키텍트 검토: 가장 큰 기술 위험은 SpriteKit이 아니라 사용자가 iPhone을 보는 동안 Watch 앱의 전면 실행·motion sampling·즉시 메시지가 유지되는지 여부이다. 이 항목은 실기기에서 먼저 검증해야 한다.

## Architecture

### Targets And Files

```text
WatchCarRacer.xcodeproj
WatchCarRacer/
  Shared/
    ControllerMessages.swift
  iOS/
    App/
      WatchCarRacerApp.swift
      GameRootView.swift
      GameSessionController.swift
    Input/
      PhoneWatchSession.swift
      TouchSteeringState.swift
      SteeringInputRouter.swift
    Game/
      GameSimulation.swift
      RoadProjection.swift
      GameScene.swift
    Feedback/
      PhoneFeedbackPlayer.swift
    Resources/
      Assets.xcassets
      Sounds/
  Watch/
    App/
      WatchCarRacerWatchApp.swift
      SteeringControlView.swift
    Motion/
      MotionSteeringEngine.swift
    Connectivity/
      WatchControllerSession.swift
    Feedback/
      WatchHapticPlayer.swift
    Resources/
      Assets.xcassets
WatchCarRacerTests/
  ControllerMessagesTests.swift
  SteeringInputRouterTests.swift
  GameSimulationTests.swift
  RoadProjectionTests.swift
WatchCarRacerWatchTests/
  MotionSteeringEngineTests.swift
```

- `ControllerMessages.swift`만 두 앱 타깃에 함께 포함한다. 공유 파일 하나를 위해 별도 Swift package를 만들지 않는다.
- `GameSimulation`은 Foundation만 import하는 결정론적 모델이며 SpriteKit, SwiftUI, UIKit, WatchConnectivity, CoreMotion을 알지 못한다.
- `RoadProjection`은 게임 좌표를 화면 위치·스케일로 바꾸는 순수 계산만 담당하고 SpriteKit 노드를 소유하지 않는다.
- `GameScene`은 고정 시간 간격으로 시뮬레이션을 진행하고 snapshot을 노드로 표현하지만, 연결 상태나 보정 규칙을 결정하지 않는다.
- 각 프로세스에서 `WCSession.default`는 하나의 어댑터만 소유한다. iPhone은 `PhoneWatchSession`, Watch는 `WatchControllerSession`이 delegate 수명과 executor 전환을 담당한다.
- Swift 6 concurrency warning을 광범위한 suppress나 무분별한 `@unchecked Sendable`로 숨기지 않는다.

### Core Contracts

- `SteeringPacket`: 프로토콜 버전, stream UUID, 단조 증가 sequence, `needsCalibration|active|motionUnavailable` 상태, 유한하고 clamp된 `-1...1` 값
- `WatchFeedbackPacket`: 프로토콜 버전, event UUID, `nearMiss|collision` 종류
- `SteeringSnapshot`: 현재 값, `watch|touch` 입력 원천, 사용 가능 상태
- `SteeringInputProviding`: iPhone 로컬 단조 시각에서 유효한 `SteeringSnapshot` 제공
- `MotionSampling`: 합성 motion으로 보정·축·wrap·필터를 검사할 수 있는 Core Motion seam
- `SteeringTransport`: 실제 WCSession 없이 전송 주기와 오류를 검사할 수 있는 transport seam
- `GameSimulation.reset(seed:)`, `step(dt:steering:) -> [GameEvent]`: seed 기반 장애물 생성과 월드 상태 갱신
- `GameSnapshot`: 차량, 장애물, 점수, 속도, phase를 담는 값 타입

### Runtime Flow

1. 두 앱은 시작 시 `WCSession`을 활성화한다. iPhone은 Watch 상태와 무관하게 터치 입력으로 즉시 플레이 가능하다.
2. Watch는 연결 상태와 “중립 자세로 보정” 버튼을 보여준다. 보정하면 motion 사용 가능 여부를 확인하고 중립 자세, 새 stream UUID, 초기 sequence를 설정한다.
3. Watch는 약 50Hz로 최신 자세를 샘플링한다. 실제 검증된 상대 각도를 데드존·풀록 범위로 `-1...1`에 매핑하고 약 50ms 시정수의 시간 기반 low-pass filter를 적용한다.
4. 별도 30Hz sender가 최신 값만 `sendMessageData`로 보낸다. unreachable일 때는 전송을 건너뛰며 지연 전달되는 background queue를 사용하지 않는다.
5. iPhone은 버전, 상태, finite/range, stream, sequence를 검증한 뒤 iPhone 자신의 단조 시계로 수신 시각을 기록한다. 서로 다른 기기의 timestamp 차이로 one-way latency를 계산하지 않는다.
6. 입력 라우터는 active 패킷이 있고, session이 reachable이며, 수신 후 250ms 이내일 때만 Watch를 선택한다. 그 외에는 마지막 Watch 조향을 폐기하고 100~150ms 동안 중립으로 blend한 뒤 터치를 선택한다.
7. Watch가 정상일 때는 Watch가 우선한다. 재연결 시 사용자가 이미 터치 drag 중이면 손을 뗄 때까지 Watch가 입력을 빼앗지 않고, 그 후 짧게 blend한다.
8. `GameScene.update`는 입력 snapshot 하나를 읽고 1/60초 fixed-step accumulator로 `GameSimulation`을 진행한다. 긴 frame time은 cap하며 SpriteKit physics frame을 판정의 기준으로 쓰지 않는다.
9. 시뮬레이션은 차량 횡속도, 도로 경계, 장애물 깊이, 월드 좌표 AABB 충돌, 근접 회피, 점수와 난이도 cap을 계산한다. 모든 spawn row에는 반드시 통과 가능한 공간을 남긴다.
10. 근접 회피와 충돌 이벤트는 화면 효과, 사운드, iPhone 햅틱, 도달 가능할 때의 Watch 햅틱을 한 번만 발생시킨다. Watch 피드백 실패는 게임 결과를 바꾸지 않는다.
11. Watch 앱이 inactive가 되면 motion을 중지하고 보정값을 폐기한다. 다시 활성화되면 재보정하여 자세 점프를 막는다.

## Subgoals

- [x] SG1: iPhone·Watch 동반 Xcode 프로젝트와 공유 계약 구성
  - Outcome: 빈 저장소에서 iPhone 앱, non-independent Watch 동반 앱, iOS/watchOS 테스트 타깃이 각각 빌드되고 두 앱이 최소 SwiftUI 화면을 표시한다.
  - Work: `WatchCarRacer.xcodeproj`, `WatchCarRacer/Shared/ControllerMessages.swift`, `WatchCarRacer/iOS/App/`, `WatchCarRacer/Watch/App/`, 두 테스트 디렉터리를 만든다. iOS 18/watchOS 11, Swift 6, iPhone 전용, 좌·우 가로 방향, Watch embedding, `NSMotionUsageDescription`을 설정한다. shared packet encode/decode와 DEBUG 상태 표시의 최소 뼈대를 추가한다.
  - Verify:
    - `xcodebuild -project WatchCarRacer.xcodeproj -list`에서 4개 타깃과 필요한 scheme을 확인한다.
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' build`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' build`
    - packet round trip, 미지원 버전 거부, NaN/무한대/range 거부, sequence 역행 거부 단위 테스트가 통과한다.
  - Depends on: None

- [x] SG2: Watch 실시간 조향 tracer와 자동·시뮬레이터 검증
  - Outcome: Watch 보정·조향 패킷이 iPhone tracer를 움직이는 경로가 자동 테스트와 paired simulator에서 검증되고, 실제 손목 축·부호·수명·피로 검증 항목은 SG7에 명시적으로 남는다.
  - Work: `MotionSteeringEngine`, `WatchControllerSession`, `PhoneWatchSession`의 조향 tracer만 구현한다. motion은 약 50Hz, 최신값 전송은 약 30Hz로 분리한다. Watch simulator에는 `#if DEBUG && targetEnvironment(simulator)` 전용 left/center/right 합성 입력을 제공한다. iPhone DEBUG overlay에 현재 source, packet age, sequence gap, reachability를 표시한다. 아직 실제 게임은 구현하지 않는다.
  - Verify:
    - 합성 motion으로 각도 wrap, 보정, dead zone, clamp, 시간 기반 smoothing, 좌우 부호를 단위 테스트한다.
    - 페어링 시뮬레이터에서 합성 Watch 입력이 iPhone steering bar에 전달되고 packet 오류가 앱을 중단시키지 않는다.
    - paired simulator에서 실시간 WatchConnectivity가 비대칭이 되더라도 양쪽 앱의 활성화, 메시지 전달, packet 오류 무중단 처리 증거와 재현 가능한 한계를 기록한다.
    - local monotonic clock 기반 단위 테스트에서 250ms까지 fresh, 251ms부터 stale이고 active interarrival p95 계산이 정확해야 한다.
    - 실제 iPhone/Watch의 3분 조향, 화면 어두워짐, p95 100ms 미만, 250~300ms fallback, 손목·크라운별 부호와 full-lock 편안함은 사용자 결정에 따라 후속 실기기 검증으로 이관하며 구현 완료를 차단하지 않는다.
  - Depends on: SG1

- [x] SG3: 결정론적 headless 게임 시뮬레이션 구현
  - Outcome: 렌더러 없이 자동 전진, 연속 조향, 두 장애물, 난이도 상승, 점수, 근접 회피, 충돌, 재시작을 재현 가능한 seed로 실행할 수 있다.
  - Work: `GameSimulation.swift`와 해당 테스트를 구현한다. 도로는 세 차선 너비를 가지되 차량은 연속 횡좌표로 움직인다. spawn row는 한 차선만 막아 항상 회피 공간을 남긴다. 속도와 spawn cadence는 첫 약 60초 동안 상한까지 상승한다. road barrier와 closing speed가 다른 slow traffic car를 추가한다. 충돌과 near-miss는 월드 좌표 AABB로 각각 한 번만 발생시킨다.
  - Verify:
    - 같은 seed와 입력 sequence가 동일 snapshot/event sequence를 만든다.
    - spawn row가 전체 도로를 막지 않고 장애물이 유효한 범위에만 생성된다.
    - 좌우 경계 clamp, 속도/cadence 상한, 충돌 1회, near-miss 1회, 점수 증가, crash 후 reset을 단위 테스트한다.
  - Depends on: SG2

- [x] SG4: 터치로 완주 가능한 iPhone 2.5D 세로 슬라이스 구현
  - Outcome: Watch 없이도 iPhone 가로 화면에서 시작, 조향, 회피, 충돌, 점수 확인, 즉시 재시작의 한 판 흐름이 완성된다.
  - Work: `RoadProjection`, `GameScene`, `GameSessionController`, `GameRootView`, `TouchSteeringState`를 구현한다. 사다리꼴 도로, horizon, 흐르는 차선, 깊이에 따른 위치·scale, 블록형 차량/장애물과 최소 HUD를 코드 기반 노드로 표현한다. 화면 하단 수평 drag를 `-1...1`로 만들고 release 시 spring-to-center 처리한다. collision은 projected node frame이 아니라 SG3 월드 좌표 결과만 사용한다.
  - Verify:
    - `RoadProjectionTests`에서 depth에 따른 scale/위치 단조성, 좌우 대칭, 화면 경계를 검사한다.
    - iPhone 17 Pro Max 및 사용 가능한 작은 iPhone simulator에서 좌·우 landscape safe area, 도로 전폭 도달, touch 중앙 복귀, 한 판과 재시작을 수동 확인한다.
    - 빌드 destination과 target device family에 iPad가 포함되지 않았음을 확인한다.
  - Depends on: SG3

- [x] SG5: Watch 우선 입력 라우팅과 안전한 터치 fallback 통합
  - Outcome: 신선한 Watch 입력은 차량을 조향하고, 끊김·오래된 패킷·Watch 종료 시 차량이 마지막 방향에 고정되지 않은 채 터치로 이어지며, 재연결도 입력을 갑자기 빼앗지 않는다.
  - Work: `SteeringInputRouter`를 fake monotonic clock으로 테스트 가능하게 구현하고 SG2 transport를 실제 게임에 연결한다. fresh Watch 우선, 250ms freshness, neutral blend, active touch drag 보호, release 후 Watch takeover blend, 재활성화 시 재보정 요구, 짧은 fallback banner를 추가한다.
  - Verify:
    - fresh Watch 우선, stale/unreachable fallback, 마지막 turn 폐기, neutral blend, touch drag 중 재연결, release 후 takeover를 단위 테스트한다.
    - fake clock과 simulator 가능한 범위에서 Watch 종료·reachability 손실·재연결·재보정 상태를 검증한다.
    - 자동 검증에서 어떤 손실 시나리오도 차량을 300ms 넘게 마지막 Watch 방향으로 유지하지 않고 터치가 선택되어야 한다. 실제 iPhone lock/unlock 및 실기기 인계는 후속 실기기 검증으로 이관한다.
  - Depends on: SG4

- [x] SG6: 독자적 비주얼과 박진감 피드백 완성
  - Outcome: 속도 상승과 위험한 근접 회피가 시각·청각·촉각으로 명확하게 느껴지고, 다른 게임의 에셋이나 식별 가능한 디자인을 복제하지 않은 원본 표현을 갖는다.
  - Work: 독자 팔레트, flat shadow, block-built 차량/장애물, 길가 오브젝트와 패럴랙스, 속도에 따른 lane motion을 추가한다. near-miss에는 짧은 camera punch/flash와 점수 pop, collision에는 shake/파티클/화면 전환을 사용한다. 이벤트별 iPhone haptic, best-effort Watch haptic, 권리가 명확한 짧은 engine/near-miss/collision 사운드를 연결한다. event UUID로 중복 피드백을 막는다.
  - Verify:
    - near-miss와 collision 피드백이 이벤트당 한 번만 발생하고 Watch가 unreachable이어도 게임 상태와 iPhone 피드백은 동일하다.
    - 프로젝트에 포함된 모든 이미지·사운드의 출처 또는 자체 제작 여부를 확인한다.
    - 차량·장애물·팔레트·UI가 특정 참고 게임의 캐릭터·실루엣·구성을 직접 모사하지 않는지 수동 확인한다.
    - 실제 플레이에서 속도 증가, 근접 회피, 충돌의 세 상태를 서로 구별할 수 있다.
  - Depends on: SG5

- [x] SG7: 전체 자동 테스트 및 시뮬레이터 인수 검증
  - Outcome: 전체 자동 테스트와 5분 시뮬레이터 주행에서 touch 조향·fallback·게임 흐름·프레임 안정성이 MVP 기준을 충족하고, 실기기에서 확인할 항목이 최종 검증 목록으로 명확히 남는다.
  - Work: 모든 단위 테스트를 정리하고 DEBUG 진단으로 5분 simulator soak를 수행한다. calibration 안내와 fallback banner의 문구·상태를 다듬되 새로운 기능은 추가하지 않는다. 발견된 결함만 해당 소유 모듈에서 수정한다.
  - Verify:
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacer -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max,OS=26.4' test`
    - `xcodebuild -project WatchCarRacer.xcodeproj -scheme WatchCarRacerWatchApp -destination 'platform=watchOS Simulator,name=Apple Watch Series 11 (46mm),OS=26.4' test`
    - iPhone simulator에서 touch 조향 → 근접 회피 경로 → fallback 상태 → 충돌 → 재시작을 포함해 5분간 주행하고 앱 정지·상태 손상 없이 대략 60fps를 유지한다.
    - paired simulator에서 가능한 범위의 Watch 패킷과 fallback 진단을 기록한다. 실제 보정·손목 방향·화면 어두워짐·p95·기기 햅틱은 사용자 결정에 따라 후속 실기기 검증에 남기며 SG7 PASS를 차단하지 않는다.
  - Depends on: SG6

## Final Verification

- Xcode의 iOS·watchOS scheme이 경고를 숨기지 않고 빌드되며 전체 단위 테스트가 통과한다.
- iPhone simulator의 5분 이상 연속 실제 터치 조향에서 앱 정지나 상태 손상 없이 충돌과 즉시 재시작을 반복하고 대략 60fps를 유지한다.
- paired simulator에서 가능한 Watch 연결 진단을 기록하고, 패킷이 없거나 Watch가 중단된 상태에서 마지막 방향 고정 없이 안전한 touch fallback이 유지된다.
- Watch가 없거나 중단되어도 사용자는 터치 조향으로 동일한 한 판 흐름을 끝낼 수 있다.
- 자동 전진, 두 장애물, 난이도 상승, 점수, 근접 회피, 충돌, 즉시 재시작이 모두 관찰된다.
- 2.5D 원근, 속도 연출, 근접 회피와 충돌 피드백이 구별되며 에셋과 디자인의 독자성이 확인된다.
- iPad 지원, 서버, 계정, 결제, 리더보드, 타사 엔진, 부적절한 백그라운드 권한이 프로젝트에 추가되지 않았다.

## Deferred Physical Device Verification

사용자가 실제 iPhone과 Apple Watch를 확보할 수 있을 때 별도로 수행한다. 2026-08-23 사용자 결정에 따라 아래 항목은 현재 구현 완료와 아카이브를 차단하지 않는다.

- 페어링된 실제 iPhone과 Apple Watch에서 중립 보정 안내를 이해할 수 있고, 편안한 손목 회전이 올바른 좌우 조향으로 연결되는지 확인한다.
- Watch 화면이 어두워지는 상황과 일시적 reachability 손실을 포함해 3~5분 주행하며 장시간 입력 정지나 마지막 방향 고정이 없는지 확인한다.
- 실제 active packet interarrival p95가 100ms 미만인지, 손실 시 250~300ms 이내에 fallback하는지 측정한다.
- 좌우 손목·Digital Crown 방향별 조향 부호, full-lock 편안함, 실제 iPhone/Watch 햅틱과 음향을 확인한다.

## Progress

- 2026-08-20: Ralph 실행을 시작했다. SG1부터 구현자와 독립 테스터를 순차 실행한다.
- 2026-08-20: SG1 PASS — 정확히 4개 타깃과 2개 공유 scheme을 구성했고 iPhone/Watch 빌드, iOS 패킷 테스트 6개, Watch smoke test 1개, 두 앱 시뮬레이터 실행을 독립 검증했다.
- 2026-08-20: SG2 BLOCKED — Watch/iPhone tracer 구현, 양쪽 빌드, iOS 10개 및 Watch 8개 테스트, paired simulator의 `motionUnavailable` 실시간 메시지 전달은 통과했다. 연결 가능한 실제 iPhone/Apple Watch가 없어 필수 3분 손목 조향 go/no-go 검증은 수행하지 못했다.
- 2026-08-20: 사용자 결정으로 실기기 검증을 SG7/최종 검증으로 이관하고 구현을 재개했다. SG2는 수정된 자동·시뮬레이터 기준으로 독립 재검증한다.
- 2026-08-20: SG2 PASS — iPhone/Watch Swift 6 빌드, iOS 10개와 Watch 8개 테스트, paired simulator의 Watch→iPhone 메시지 전달 및 오류 무중단 처리를 독립 재검증했다. 실기기 조향 검증은 SG7에 남겼다.
- 2026-08-20: SG3 PASS — Foundation 전용 seed 기반 시뮬레이션과 테스트 9개를 구현했다. 전체 iOS 19개, Watch 8개 테스트와 양쪽 빌드, 독립 결정론 재현을 통과했다.
- 2026-08-20: SG4 PASS — SpriteKit 2.5D 도로, touch 조향, HUD, 충돌·Retry 흐름과 projection/controller 테스트를 구현했다. iOS 29개, Watch 8개 테스트, 두 가로 방향과 두 iPhone 크기의 실제 시뮬레이터 플레이를 독립 검증했다.
- 2026-08-20: SG5 PASS — 250ms freshness, 125ms blend, touch drag 보호, stale sample 폐기와 Retry reset을 갖는 단일 입력 라우터를 구현했다. iOS 41개, Watch 8개 테스트와 독립 fake-clock 손실 probe를 통과했다.
- 2026-08-21: SG6 PASS — 독자적인 코드 기반 roadside/차량/충돌 연출, 절차 생성 음향, iPhone·Watch feedback fan-out과 UUID dedup을 구현했다. iOS 48개, Watch 11개 테스트와 시각·에셋 감사를 통과했다.
- 2026-08-21: 사용자 결정에 따라 SG7도 자동·시뮬레이터 인수 검증으로 실행하고 실제 iPhone/Watch acceptance는 최종 검증에만 남긴다.
- 2026-08-21: SG7 구현자 검증 PASS — iOS 50개와 Watch 11개 테스트, Debug·Release 양쪽 빌드, 18,000-step 회귀와 실제 301초 simulator soak를 통과했다. soak는 touch drag 78회, 충돌·Retry 23회, 평균 59.761fps, 프로세스/UI 실패 0회를 기록했다.
- 2026-08-21: SG7 독립 검증 BLOCKED — 독립 테스트와 Release 빌드는 통과했으나 host Mac 잠금으로 커스텀 touch surface의 좌우 drag·Retry를 별도 300초 세션에서 실행할 수 없었다. 사용자 지시에 따라 SG7에서 멈추고 최종 검증·아카이브를 실행하지 않는다.
- 2026-08-23: 사용자 요청으로 Ralph를 재개했다. SG7 독립 300초 touch/retry soak를 다시 실행하고, 실물 iPhone/Apple Watch 검증은 후속 항목으로 보존한 채 가능한 최종 검증과 완료 아카이브를 진행한다.
- 2026-08-23: SG7 PASS — 독립 테스터가 iOS 50개와 Watch 11개 테스트, 310초 단일 프로세스 simulator soak, 실제 touch surface 좌우 drag 10회, 충돌 후 Retry 7회, touch fallback과 paired Watch 진단을 검증했다. 종료 상태는 RUNNING, 평균 59.9fps, 최저 53fps였고 fatal/termination은 없었다.
- 2026-08-23: Final Verification 1차 FAIL — 제품 동작, 전체 테스트, Release 빌드, 범위 감사는 통과했으나 `Implementation Result`의 과거 SG7 요약만 미체크 상태였다. 현재 검증 결과에 맞게 계획 메타데이터를 수정하고 2차 검증을 요청했다.
- 2026-08-23: Final Verification 2차 PASS — 모든 SG 체크와 완료 요약이 일치하고, iOS 50개·watchOS 11개 테스트, 양쪽 Release 빌드, 독립 310초 soak, 기능·정책 범위 감사를 전체 계획 기준으로 통과했다.

## Risks

- **Watch 실행 수명 (deferred go/no-go):** 실시간 `sendMessageData`는 양쪽 앱의 활성 상태와 reachability에 의존한다. 사용자가 iPhone을 보는 동안 Watch 앱이 지나치게 빨리 suspend되면 핵심 조작이 성립하지 않을 수 있다. 사용자 결정에 따라 현재 구현 완료와 별개로 후속 실기기 검증에서 결론을 낸다.
- **손목 제스처 모호성:** Euler axis를 미리 고정하면 손목·크라운 방향에 따라 반대 또는 불편한 조향이 될 수 있다. 각도 추출을 seam 뒤에 두고 실기기에서 axis 또는 quaternion projection을 결정한다.
- **지연과 jitter:** 30Hz interactive message도 배터리 비용과 편차가 있다. Watch는 최신값만 보내고 iPhone 로컬 수신 시각, sequence gap, p95 간격을 DEBUG에서 측정한다.
- **입력 원천 flapping:** `isReachable`만으로 즉시 전환하면 차량이 흔들릴 수 있다. 250ms freshness와 짧은 source blend, active touch drag 보호를 함께 사용한다.
- **시뮬레이터의 거짓 확신:** 합성 motion과 paired simulator는 schema·transport만 검증한다. 자세, 축, 피로, 화면 어두워짐, 실제 지연에 대한 실기기 acceptance는 여전히 미완료이다.
- **2.5D 시각과 충돌 불일치:** 투영된 node frame으로 충돌을 판단하면 원근 scale이 게임 규칙을 바꾼다. 충돌은 항상 world coordinate simulation에서 계산한다.
- **참고작 모방 위험:** 친근한 로우폴리 분위기만 참고하고 비율·실루엣·팔레트·길가 오브젝트·UI·사운드는 원본으로 만든다.
- **손목 피로:** 30도 full-lock 제안도 실제로 불편할 수 있다. SG2의 3분 자세 테스트에서 데드존과 범위를 조정하고 극단 회전을 요구하지 않는다.

## Open Questions

- 후속 실기기 검증에서 일반적인 Watch 전면 실행 수명으로 3분 이상 실시간 제어가 유지되는가? 실패하면 Watch 조작 방식 자체를 수정할지, Apple 정책상 정당한 실행 범주가 실제로 존재하는지 조사할지, Watch 컨트롤러 접근을 중단할지 사용자 결정이 필요하다.
- 어떤 motion 축 또는 quaternion projection이 정의한 중립 자세에서 가장 자연스러운 운전대 회전을 표현하는가? 좌우 손목·크라운 방향별 실기기 측정으로 확정한다.
- iOS 18/watchOS 11 및 iPhone 가로 전용 가정이 실제 배포 대상과 다르면 구현 시작 전에 deployment target과 화면 범위를 갱신한다.

## Implementation Result

Implemented on 2026-08-23.

### Summary

- iPhone·Watch 동반 프로젝트, Watch motion/WatchConnectivity tracer, seed 기반 게임 시뮬레이션, SpriteKit 2.5D 터치 플레이, Watch/touch 입력 라우팅, 독자적 비주얼·절차 음향·iPhone/Watch feedback을 구현했다.
- 모든 구현 subgoal과 simulator acceptance를 독립 검증했다. 실물 iPhone/Apple Watch acceptance는 사용자 결정에 따라 후속 항목으로 보존한다.

### Completed Subgoals

- [x] SG1: iPhone·Watch 동반 Xcode 프로젝트와 공유 계약 구성
- [x] SG2: Watch 조향 tracer와 자동·시뮬레이터 검증 완료
- [x] SG3: 결정론적 headless 게임 시뮬레이션
- [x] SG4: 터치로 완주 가능한 iPhone 2.5D 세로 슬라이스
- [x] SG5: Watch 우선 입력 라우팅과 안전한 touch fallback
- [x] SG6: 독자 비주얼과 near-miss/collision feedback
- [x] SG7: 전체 자동 테스트와 독립 310초 simulator acceptance

### Changed Files

- `WatchCarRacer.xcodeproj/`: iPhone·Watch 앱 및 테스트 타깃과 scheme 구성
- `WatchCarRacer/`: 공유 패킷, Watch 조향 전송, iPhone 입력 라우팅, 게임 시뮬레이션·렌더링·피드백 구현
- `WatchCarRacerTests/`: iOS 계약·입력·시뮬레이션·투영·피드백 회귀 테스트
- `WatchCarRacerWatchTests/`: Watch motion·연결·피드백 회귀 테스트

### Verification

- iOS full tests: 50/50 passed.
- watchOS full tests: 11/11 passed.
- iOS/watchOS Release simulator builds: passed without Swift/Clang compiler warnings.
- Independent simulator soak: 310초 단일 프로세스, 좌우 touch drag 10회, collision/Retry 7회, 종료 상태 RUNNING.
- Runtime FPS: 평균 59.9, 최저 53.0, fatal/exception/termination 0회.
- Scope audit: iPhone-only이며 금지된 서비스·타사 엔진·부적절한 capability가 없다.
- Final verification attempt 2: passed.

### Follow-ups

- 실제 iPhone/Apple Watch에서 보정 자세, 조향 부호와 편안함, 화면 어두워짐 시 실행 수명, 실제 packet p95/fallback, 햅틱·음향을 검증한다.
