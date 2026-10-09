# Wrist Magic / 腕术 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking. 默认建议 inline/native 执行；未经用户选择，不启动子代理。

**Goal:** 交付原生 Apple Watch + iPhone 腕术：三术、Crown 蓄力、动作与触感、Reality 实时舞台、Show Off 六秒成片，遵循方向 1 黑金设计。

**Architecture:** 双 SwiftUI Target，共享 WristMagicCore 纯逻辑包；Watch 管理动作输入与本地反馈，iPhone 管理联网许可、AR 舞台、录制和文件。ARKit + Metal 生成同一预览/导出帧，AVFoundation 负责视频与应用音效，所有后台/断连路径显式撤销许可。

**Tech Stack:** Swift 6 language mode、SwiftUI、Core Motion、WatchKit、WatchConnectivity、ARKit、Metal、AVFoundation、PhotoKit、XCTest；无第三方运行时依赖。

**Spec:** [DESIGN.md](../../../DESIGN.md)。执行前同时阅读完整设计、本文、当前仓库 AGENTS.md；新仓库不存在时不能虚构原有文件和测试结果。

## Global Constraints

- 最低部署 iOS 17 / watchOS 10；Swift 6 language mode；Xcode 由 T01 根据真机系统确定并记录 build number。
- 首版仅后置相机、竖屏，720×1280、30fps、SDR H.264 MP4；Show Off 固定 6 秒、3 秒倒计时、单次施法。
- 黑金方向 1 唯一基线；x4/x5/x8/x9 定稿；x6/x7 禁用。
- 仅 foreground 施法；无 workout 保活、全天监听、手掌/手指追踪、任意触感波形。
- Watch 本地选术与蓄力；iPhone 联网会话、许可、录制时间权威；不比较两设备绝对时钟。
- 即时 cast 不进入持久后台传输队列；同 eventID 重试不能重复施法。
- 预览与导出共用合成器；相机 UI 不能进入视频；不循环 snapshot 冒充视频。
- 无麦克风录音；音轨为应用法术音效；关闭声音时导出静音。
- 所有性能、动作识别、签名和 AR 结论需要实测；当前没有已完成的 Apple 工程。
- 代码实施不在本轮授权范围；文件交付后等待用户审阅和选择执行方式。

## Review Focus

1. 抬腕后锁屏/进入后台/断连，用户应明确暂停，恢复不能回放旧施法；T06/T09/T18 负责测试。
2. 左右腕和表冠方向、低幅度动作、喝水等负例不能被一套固定轴阈值误判；T02/T04 负责保留集。
3. 跨设备乱序/重复/过期与版本不匹配应拒绝且无副作用，ACK 丢失不能重施法；T05/T06 测试。
4. Writer 背压、磁盘不足、帧方向、后台中断不能产出假成功视频，也不能无限累积内存；T07/T12/T16 测试。
5. 最大文字、VoiceOver、静音/无触感与相机/相册拒绝时仍有清楚出口；T08/T17/T19 测试。

---

## 0. 执行约定与里程碑

本文是可审阅的完整计划，未执行。所有 `Evidence/` 文件由对应任务写入实测数据，禁止预填 PASS。修改 task 的契约要先更新 DESIGN 与引用者再继续。每个任务做完独立 commit；命令失败先找根因，不以截图“看起来正常”掩盖。

任务内的测试断言是测试契约；实现者将其写成实际 XCTest，测试入口与夹具由所属任务创建。硬件/美术/签名任务使用可复现清单而不造无价值单元测试。每项先验证失败再最小实现再通过，纯文档与资源入库不强行 RED/GREEN。

| 阶段 | 任务 | 完成后用户拿到什么 |
|---|---|---|
| M0 | T01–T07 | 可安装验证壳、Motion 数据、连接时延、6秒带合成效果样片 |
| M1 | T08–T09 | 可独立练习三种腕术的 Watch 应用 |
| M2 | T10–T14 | 完整教学、连接与 Reality 舞台 |
| M3 | T15–T17 | 固定构图拍摄、导出、回放与分享 |
| M4 | T18–T22 | 异常收口、无障碍、性能、美术一致性、安装交付 |

关键路径：T01 → T02/T03 → T04；T01 → T05 → T06；T01 → T07。三个探针 T02/T06/T07 都通过才进入生产 polish。任务标注并行可能性只是依赖信息，不代表授权派出子代理。建议在同一工程按顺序做，降低接口漂移。

工时仅为规划估算：单名熟悉 Swift 的工程师约 15–25 个工作日；M0 3–5 日，Watch 2–3 日，Reality 3–5 日，Show Off 4–6 日，质量收口3–6日。硬件不可用、Motion 泛化不足和特效资产制作可能延长；不是 Agent 自动执行时长承诺。

## 1. 工程文件图

严格采用 DESIGN §7 的文件布局。扩展如下：

- 核心测试位于 `Packages/WristMagicCore/Tests/WristMagicCoreTests/`，文件对应 `CastReducerTests.swift`、`GestureGateTests.swift`、`EventGateTests.swift`、`ClipTimelineTests.swift`、`EffectTimelineTests.swift`。
- iOS 集成测试 Target/scheme `WristMagic-iOS-Tests`；Watch 集成测试 scheme `WristMagic-Watch-Tests`；App schemes `WristMagic-iOS` / `WristMagic-Watch`。
- 纯逻辑脚本 `scripts/test-core.sh` 执行 `swift test --package-path Packages/WristMagicCore`。
- `scripts/test-ios.sh` / `test-watch.sh` 读取 `IOS_SIMULATOR_ID` / `WATCH_SIMULATOR_ID`，未设置时列出目的地并失败，禁止猜 UDID；调用对应 scheme 的 xcodebuild test、生成 `.xcresult`。
- 所有运行证据保存到 `Evidence/<topic>/<runID>/`，索引含 commitSHA、设备型号、OS build、Xcode build、运行命令、观察、通过/失败。
- 原型素材为本包中的五张参考图；`Resources/ASSET-MANIFEST.md` 是生产素材来源表，与设计参考分开。

## T01：可安装双端工程与环境基线

**依赖：** 无。**Files：** Create `WristMagic.xcodeproj`、`Packages/WristMagicCore/Package.swift`、两个 App 入口、`Tests/Fixtures/TestFactory.swift`、上述三个 test 脚本、`Evidence/environment/README.md`。

**Interfaces：** Produces 三个脚本、四个 schemes、两 App 与可被两端 import 的 `WristMagicCore`。Consumes DESIGN §2/7/14。

- [ ] 记录 `xcodebuild -version`、`xcodebuild -showsdks`、`xcrun simctl list devices available`、`xcrun devicectl list devices`；在 Xcode 检查 Watch 配对可部署状态。记真实 iPhone/Watch/系统，签名团队类别，不记录证书私钥。
- [ ] 新建原生双端项目，设置 iOS17/watchOS10、Swift6、Debug/Release、共享 schemes；使用自有反向域名 bundle ID，实际 ID 记环境文件，不虚构用户组织。
- [ ] 创建核心包及 XCTest Target，写 `testCoreModuleImportsOnBothPlatforms` 验证两端链接；不加入 HealthKit/后台录音等无关 capability。
- [ ] 脚本缺 UDID 时应 exit 非0并给出设置变量说明；提供有效 UDID 后测试成功且产出 xcresult。shell 使用 `set -euo pipefail`。
- [ ] 将最小启动页装入配对真机，两端均可前台打开。Personal Team 安装失败须记录签名错误并停止硬件依赖任务；模拟器只可推进纯 UI/Core。
- [ ] Commit `chore: establish native wrist magic workspace`；Evidence 中不要填未实际运行的设备结论。

**通过：** 两端真机启动+共享包可测；签名限制有清楚安装说明。**门禁：** 没有 Mac/Xcode 或真机时不把 M0 标通过。

## T02：Motion 探针、校准与数据集

**依赖：** T01。**Files：** Create `WristMagicWatch/Motion/MotionSource.swift`、`WristCalibration.swift`、`Domain/MotionSample.swift`、`Tests/Fixtures/Motion/`、`Evidence/motion/`。

**Interfaces：** Produces `@MainActor MotionSource.start(onSample: @escaping (MotionSample) -> Void) throws`、`stop()`；`WristCalibration.normalize(_ sample: MotionSample) -> MotionSample`。共享 `MotionSample` 按 DESIGN §8 显式 init，含 attitude 四元数，用于中立姿态归一化。Debug data logger 不进入 Release UI。

- [ ] 写 `testGravityExcludedAndUnitsConverted`：1g userAcceleration 转 9.80665m/s²、gravity 不重复加回；`testStopIsIdempotent`：stop 后样本回调计数不增加。
- [ ] `scripts/test-watch.sh` 确认上述失败来自未实现逻辑，然后接入 CMMotionManager 50Hz 请求、专用串行队列、可用性/错误处理，不假定实际50Hz。
- [ ] `testLeftRightNormalizationKeepsForwardSign` 用人工已知坐标夹具检查左右腕统一动作符号；表冠朝向改变不导致所有事件符号倒置。
- [ ] 按 DESIGN §9 收集训练/保留集与负例，导出仅传感器数字与匿名标签；记录 actualHz 分布、掉样、foreground/inactive 时序。
- [ ] 在真实 Watch 验证转 Crown、蓄力时的手腕扰动、抬腕/垂腕对前台可用窗口的影响。无法稳定 foreground 操作则重写交互，不开 workout 伪装绕过。
- [ ] 冻结 `motion-dataset-v1.json` 清单和采样说明；Commit `feat: capture and normalize watch motion`。

**通过：** 设备数据可用，左右腕有证据，停止采样有效；此任务不宣称动作识别已达标。

## T03：法术领域与纯状态机

**依赖：** T01。**Files：** Create `Domain/Spell.swift`、`CastState.swift`、`CastReducer.swift`、`CastReducerTests.swift`。

**Interfaces：** Consumes DESIGN §8 `SpellID/CastAction`；Produces `CastReducer.reduce(_:_:)->CastState` 与所有 public init。初始 `fireball/selecting/0`。

- [ ] 采用 DESIGN §16 可执行 XCTest 示例写 `testCannotFireBeforeArmed`，初态 `.trigger` 不变；`.prepare` 后 `.trigger` 仍不变；满 charge 仍需 `.armed` 才 ready。
- [ ] 写 `testChargeClampsAndRejectsNaN`：-0.1→0、1.4→1、NaN/Inf 不改变；`testPauseClearsCharge` charge=0/phase=paused；`testResumeReturnsToSelecting` 不自动 ready。
- [ ] 跑 `scripts/test-core.sh`，预期未定义 reducer/断言失败；实现纯函数，无设备依赖。
- [ ] `testSecondTriggerCannotFireAgain`、`testSpellChangeDuringReadyIsIgnored`、`testTimeoutLeavesRetryState` 通过；700ms 限流由 T04 gate 控制，不能藏在纯 reducer 的系统时钟中。
- [ ] 全部核心测试通过；Commit `feat: define casting state machine`。

## T04：动作门控与重复触发防护

**依赖：** T02/T03。**Files：** Create `Domain/GestureGate.swift`、`GestureProfile.swift`、`GestureGateTests.swift`、`Resources/MotionProfiles-v1.json`、`Evidence/motion/validation.md`。

**Interfaces：** Consumes normalized MotionSample、选定 SpellID；Produces `RuleGestureGate: GestureGate`、`GestureProfile`、`GestureTrigger.update(sample:state:now:)->GestureDecision?`，`now:Double` 为单机秒。

- [ ] 用保留前的训练样本编写 `testUnarmedNeverTriggers`、`testOneImpulseEmitsOneDecision`、`testCooldown700ms`；cooldown 内重复窗返回nil，超过窗口且重新 ready 可触发。
- [ ] 写 `testStationaryCrownRotationIsNegative`、`testDownSlashOnlyEvaluatesSelectedSpellProfile`。门控只检查当前术，不依靠握拳/掌心检测。
- [ ] `scripts/test-core.sh` 先 RED；实现400ms中立窗口、600ms特征窗，数值阈值从训练集选定写入 profile，处理采样断档>200ms 时清空窗口。
- [ ] profile冻结后独立运行保留集：每术总命中≥90%、每术每腕≥85%、armed≤1误触/10min、unarmed0；结果含分母。达不到就阻断并报告，不偷偷用测试集调阈值。
- [ ] 真机20次连续施法无一次重复事件；Commit `feat: gate intentional wrist gestures`。

## T05：消息协议、许可与纯事件门禁

**依赖：** T03。**Files：** Create `Protocol/WireEnvelope.swift`、`SessionPermit.swift`、`EventGate.swift`、`EventGateTests.swift`。

**Interfaces：** Consumes DESIGN §8 全部协议；Produces `EventGate.accept(_ envelope:WireEnvelope, now:Double)->Receipt`、`grant(sessionID:spell:now:validFor:)->SessionPermit`、`reset(sessionID:)`；通过构造注入 UUID 生成器，测试固定 ID。payload类型逐项定义：HelloPayload、SelectPayload、ArmRequestPayload、ArmGrantPayload、AckPayload、ReasonPayload、SettingsPayload。

- [ ] 写 round-trip 测试全部9种 WireKind，未知版本/enum、>16KiB、非法JSON、NaN charge、charge超0...1 返回 invalid，不发生副作用。
- [ ] 写 `testDuplicateCastReturnsDuplicateWithoutEmission`、`testOldSessionRejected`、`testExpiredPermitRejectedAtBoundary`：now==deadline 必须 stale。
- [ ] 写 `testWrongSpellAndTokenRejected`、`testSequenceRollbackRejected`；去重需先于 sequence 检查，否则同ID重试误当新包。
- [ ] `scripts/test-core.sh` RED→最小实现 receiver单调时钟deadline、每permit单次、最多256事件缓存；reset 清空。
- [ ] `testDuplicateReturnsOriginalAcknowledgement` 验证 duplicate带原receipt，发起端不会无限重试；Commit `feat: define idempotent live casting protocol`。

## T06：WatchConnectivity 探针与握手

**依赖：** T01/T05。**Files：** Create `WristMagicWatch/Connectivity/WatchLink.swift`、`WristMagiciOS/Session/PhoneLink.swift`、`SessionCoordinator.swift`、`Tests/iOS/LiveLinkTests.swift`、`Evidence/link/`。

**Interfaces：** Produces `WatchLink/PhoneLink: LiveLink`；`@MainActor SessionCoordinator.receive(_ envelope:WireEnvelope, now:Double)->WireEnvelope`；`invalidate(reason:String)`；`isReady:Bool`。delegate回调切换到指定actor，UI状态仅MainActor。

- [ ] Fake transport测试 `testReachableWithoutHelloIsNotReady`、`testAckLossRetriesSameEventIDOnce`、`testReconnectCreatesNewSession`。
- [ ] RED后实现 activated/isReachable 检查和 sendMessageData、ACK：300ms一次重试、800ms超时；超时归未知结果，不能生成新cast。静态设置单独applicationContext路径。
- [ ] 写 `testCastNeverUsesBackgroundTransfer`、`testInactivePhoneRejectsCastEvenWhenReachable`、`testWatchAppNotInstalledShowsHelp`，覆盖 WCSession 生命周期和错误代理。
- [ ] 两端真机100次消息，Watch测ACK RTT P50/P95/max、成功率；断连/锁屏/退出/再连接各10次，无陈旧重放。目标P95≤300ms；不做 RTT/2 单程估算。
- [ ] 通过测试和证据后 Commit `feat: connect watch and phone casting sessions`。

**门禁：** 只能证明 transport 到达；视频和AR准备还需要独立条件。

## T07：合成录像可行性探针

**依赖：** T01。**Files：** Create `Stage/ARFrameSource.swift`、`CameraTransform.swift`、`StageRenderer.swift`、`Shaders/Camera.metal`、`Capture/ClipWriter.swift`、`Tests/iOS/CaptureProbeTests.swift`、`Evidence/capture/probe/`。

**Interfaces：** Produces `ARFrameSource.start() throws / stop()`；`StageRenderer.render(frame:ARFrame,effects:[EffectCue],target:CVPixelBuffer) throws`；`ClipWriter.start(at:CMTime) throws`、`append(buffer:CVPixelBuffer,pts:CMTime) throws -> Bool`、`finish() async throws -> URL`、`cancel()`。EffectCue 临时定义也必须按 T13 结构，不能换名。

- [ ] 写方向/裁切 fixture 测试 `testPortraitCropMapsKnownCorners`；测试素材为开发夹具棋盘，不是交付图像生成任务。
- [ ] 用 Metal 把 ARFrame YCbCr 背景+一个明确可见的金色测试环合成到720×1280 BGRA离屏缓冲；单一ARSession拥有相机。测试环可仅在 Debug；不是最终法术资产。
- [ ] 将相同缓冲显示与编码；GPU完成后append，3个buffer上限；写 `testPTSStrictlyIncreases`、`testBackpressureDoesNotGrowQueue`；未知SDK API availability 通过T01环境实编译核验。
- [ ] 真机录6秒并用 `scripts/verify-clip.sh <path>` 检查720×1280、6±0.15秒、可解码；脚本用本地AVFoundation验证程序，不强制安装ffmpeg。
- [ ] 抽查首、中、尾帧都有正确方向、特效环进入视频、SwiftUI测试按钮不进入视频；连续10段导出；保留样片和失败日志。
- [ ] Commit `feat: prove shared AR preview and video pipeline`。

**门禁：** 若只有相机原片/截图序列/含UI录屏，该探针失败。T12–T16不应继续堆完整界面掩盖。

## T08：设计 token、资源与共享组件

**依赖：** T01；完整 polish 在M0通过后。**Files：** Create `SharedUI/DesignTokens.swift`、`GoldButton.swift`、`SpellHero.swift`、`ConnectionBadge.swift`、`Resources/ASSET-MANIFEST.md`、两平台Assets.xcassets；Modify各Target资源归属。

**Interfaces：** Produces `DesignTokens`、`GoldButton(title:isEnabled:isBusy:action:)`、`SpellHero(spell:phase:reducedMotion:)`、`ConnectionBadge(state:)`；所有view MainActor。ConnectionState独立enum含waiting/connected/disconnected。

- [ ] 逐项复制 DESIGN §4 token；不从生成PNG自动取色。原型为参考资源，不直接作为页面背景图。
- [ ] 生成/制作授权独立法术美术和声音，登记尺寸/大小/来源/许可；未知授权不入发布包。Watch每术解码≤8MiB，手机效果压缩合计≤20MiB。
- [ ] 构建组件预览覆盖 default/pressed/busy/disabled、大字、VoiceOver；测试 `testBusyButtonCannotSubmitTwice`，标题与按钮尺寸不跳动。
- [ ] 在390×844和41mm/45mm截图检查金色按钮、辅助文字、边缘安全范围。颜色/字号低影响常量不写镜像单元测试；用渲染证据。
- [ ] 运行 `scripts/verify-assets.sh` 校验缺失资源和清单对应；Commit `design: establish obsidian ritual components`。

## T09：可独立玩的 Watch 完整流程

**依赖：** T03/T04/T08，联网需T06。**Files：** Create `Casting/WatchCastModel.swift`、`SpellPickerView.swift`、`ChargeView.swift`、`ReadyView.swift`、`ResultView.swift`、`Feedback/HapticPlayer.swift`、`WatchSoundPlayer.swift`、`Tests/Watch/WatchCastingTests.swift`。

**Interfaces：** `@MainActor WatchCastModel.send(_ action:CastAction)`、`state:CastState`、`setMode(_ mode:PlayMode)`；`HapticPlayer.play(_ event:FeedbackEvent,at:Double)`；FeedbackEvent=start/ready/released/retry/paused。Consumes reducer、MotionSource、GestureTrigger、LiveLink。

- [ ] UI测试选择三术→准备→Crown→就绪→测试注入动作→释放；生产不暴露注入入口。检查Crown焦点仅在当前屏，返回自动归零。
- [ ] `testBackgroundStopsMotionAndInvalidatesPermit`、`testLocalPracticeWorksWithoutPhone`、`testHapticRateLimit250ms`、`testMutedSettingDoesNotBlockState` 先RED。
- [ ] 实现离线4秒ready、700ms防重；联网等armGrant；Watch pause时stop采样/声音/动画，恢复回选择，不自动ready。
- [ ] 反馈按 DESIGN映射预设；Crown内置触感和自定义click不叠加。手机在线时Watch不放法术音效。
- [ ] 真机完成三术各20次，戴在两腕检查操作舒适性；VoiceOver替代按钮与触发共用事件门禁。
- [ ] Watch测试通过，Commit `feat: ship foreground watch spell practice`。

## T10：iPhone 连接、教学、主页与设置

**依赖：** T06/T08/T09。**Files：** Create `App/AppModel.swift`、`Entry/ConnectionView.swift`、`TutorialView.swift`、`HomeView.swift`、`Settings/SettingsStore.swift`、`SettingsView.swift`、`Tests/iOS/EntryFlowTests.swift`。

**Interfaces：** `SettingsStore.snapshot:SettingsPayload`、`update(sound:haptic:reduceMotion:)`递增revision；`AppModel.route:AppRoute`；`AppRoute`为connection/tutorial/home/reality/showOff/settings/review/recovery，关联值只带稳定ID/URL。

- [ ] 测试首次启动无教学完成记录显示引导；无Watch可以看教学，进入手机施法需要连接；教学成功文案用“这次成功了”。
- [ ] 测试 `testOlderSettingsRevisionIgnored`、`testSpellRequestWhileChargingIsDeferred`；首页改变术须Watch确认后显示选中，失败恢复旧术并说明。
- [ ] 实现 x5 首页、原生设置列表；教学不识别拳头/掌心，只演示轨迹；只有动作事件通过才进入成功页。
- [ ] 完成教学状态与三个设置存本地UserDefaults，不建数据库/账号；冷启动恢复设置，不恢复ready。
- [ ] iOS测试+四页截图通过；Commit `feat: add phone onboarding and spell home`。

## T11：Reality 舞台与位置引导

**依赖：** T06/T07/T10。**Files：** Create `Stage/EffectStage.swift`、Modify `ARFrameSource.swift`、`SessionCoordinator.swift`；Create `Tests/iOS/RealityStageTests.swift`。

**Interfaces：** `EffectStage.place(cameraTransform:simd_float4x4,mode:PlayMode,side:LaunchSide)`；`LaunchSide=left/right`；`makeCue(cast:CastPayload,start:Double,seed:UInt64)->EffectCue`。Consumes ARFrame、permit门禁；Produces固定世界锚与投影参数。

- [ ] 写 `testUnsupportedARStaysOutOfStage`、`testLimitedTrackingRejectsNewCast`、`testRepositionDisallowedWhileCasting`。
- [ ] 实现启动检查、授权入口、tracking normal等待；初始锚在相机前1.5m，不声称实际地面碰撞。重定位只在空闲提供。
- [ ] 测试相机平移后世界锚不随屏幕游走；恢复session重建锚；手表转动不伪造相机空间位置。
- [ ] 真实场景亮/暗/低纹理、相机受遮挡、旋转到横屏（UI仍竖屏）验证出口与方向。
- [ ] `scripts/test-ios.sh`通过，Commit `feat: anchor reality mode spell stage`。

## T12：正式 ClipWriter 与录制时间线

**依赖：** T07。**Files：** Create `Capture/ClipTimeline.swift`（共享包位置）、`ClipTimelineTests.swift`、`WristMagiciOS/Capture/ClipValidator.swift`；Modify `ClipWriter.swift`。

**Interfaces：** `ClipTimeline.begin(firstFrameTime:Double)`、`elapsed(at:Double)->Double`、`canCast(at:Double)->Bool`、`shouldFinish(at:Double)->Bool`；`ClipValidator.validate(url:URL,expectedDuration:Double?,requiresAudio:Bool) async throws -> ClipReport`；ClipReport含width/height/duration/hasAudio。

- [ ] 写 `testDurationStartsAtFirstFrameNotButton`：begin=10，at=15.999未满，at=16结束；`testCastCutoffAt4Point5`：4.499 true，4.5 false。
- [ ] 写 `testOutOfOrderPTSRejected`、`testWriterFailureNeverReturnsSuccessURL`、`testGPUBufferNotReusedBeforeCompletion`。
- [ ] 实现 writer串行状态idle/writing/finishing/finished/failed，重复finish复用结果，cancel幂等；availability封装在writer，不散到视图。
- [ ] 写 `testManualStopBelow2SecondsDiscardsClip`、`testPartialAt2SecondsIsMarkedInterrupted`；最后帧结束PTS符合真实时长，缺帧不能复制时间戳凑数。
- [ ] test-core + test-ios + 真机6秒样片验证；Commit `feat: make clip writing bounded and recoverable`。

## T13：三术共用效果时间线与美术

**依赖：** T08/T11/T12。**Files：** Create `Domain/EffectCue.swift`、`Capture/EffectTimeline.swift`（均共享包下）、`EffectTimelineTests.swift`、`Shaders/SpellEffects.metal`；Modify `StageRenderer.swift`、`EffectStage.swift`；更新素材清单。

**Interfaces：** `EffectCue`含`eventID:UUID,spell:SpellID,start:Double,duration:Double,seed:UInt64,origin:SIMD3<Float>,direction:SIMD3<Float>`；`EffectTimeline.evaluate(_ cue:EffectCue,at:Double,reducedMotion:Bool)->EffectParameters`；EffectParameters为已定义GPU uniforms，字段与Metal结构对齐并有大小断言。

- [ ] 写 `testSameSeedAndTimeProduceSameParameters`、`testNoEffectBeforeStart`、`testEffectEndsBy1Point5Seconds`、`testReducedMotionHasNoFlashPulse`。
- [ ] RED后实现Fireball billboard+尾迹、Lightning折线+目标短闪、Force Push扩张环；主1.2秒+尾0.3秒。资源统一色彩与亮度，不对UI主题换色。
- [ ] 渲染同一固定fixture到预览和导出，比较关键像素区域与时间点，而不是仅比较文件大小。记录0/0.3/0.8/1.5秒的参考帧。
- [ ] 验证金色UI、橙/蓝/银法术不互相染色；低配置先减粒子，不改状态反馈。
- [ ] Commit `feat: render three deterministic spell effects`。

## T14：法术音效与预览/导出同步

**依赖：** T12/T13。**Files：** Create `Capture/ClipAudioMixer.swift`、`Tests/iOS/ClipAudioMixerTests.swift`、`Resources/Sounds/`；Modify `WatchSoundPlayer.swift`、`SessionCoordinator.swift`。

**Interfaces：** `ClipAudioMixer.mix(video:URL,cues:[EffectCue],soundEnabled:Bool) async throws -> URL`；录制零点与cue转换由CaptureCoordinator提供；不读取Watch时钟。音效资源manifest记录来源。

- [ ] 写 `testMuteProducesNoAudioTrack`、`testCuePlacedAtVideoTime`、`testAudioFailureKeepsSourceVideo`；用已知开始时刻的短脉冲夹具校验≤80ms对齐。
- [ ] 实现视频完成后的AVComposition音轨混合与AAC导出；输出MP4/H264保留尺寸方向；没有现场录音与麦克风授权。
- [ ] 预览播放也用同一cue，手机在线Watch禁重复声音；本地练习Watch可发声。
- [ ] 连续10段检查声音没有逐段漂移、削波或尾音越出片长；静音保留所有交互。
- [ ] Commit `feat: synchronize spell audio with exported clips`。

## T15：Show Off 机位、倒计时与单次施法协调

**依赖：** T06/T10–T14。**Files：** Create `Capture/CaptureCoordinator.swift`、`Entry/ShowOffView.swift`、`Tests/iOS/ShowOffFlowTests.swift`；Modify `SessionCoordinator.swift`。

**Interfaces：** `CaptureCoordinator.prepare(side:LaunchSide)`、`beginCountdown() async`、`receiveCast(_ envelope:WireEnvelope)`、`stop() async`、`cancel()`；`CaptureState=preparing/countdown/recording/processing/review/failed`，关联 elapsed/clipID/error，但不把writer对象存进view。

- [ ] 写 `testCountdownDoesNotEmitEffectOrPermit`、`testPermitOnlyAfterFirstRecordedFrame`、`testOnlyOneCastAcceptedPerClip`、`testLateCastRejectedAt4Point5`。
- [ ] 实现固定手机、站位轮廓、左/右发射区；Watch蓄满以后手机才能开始倒计时；倒计时结束且首帧开始后才给予有限许可。拒绝时保留重试入口。
- [ ] 写 `testCameraMoveInvalidatesFixedComposition`：以开始位姿为基准，初始阈值平移>0.15m或转角>10°持续0.3秒中断（真机调优记ADR）；解释“请放稳手机后重拍”。
- [ ] 6秒自动收尾；未触发也可回放但不显示“施法成功”；processing期间按钮busy且防重入。
- [ ] 真机拍三术各10段，包含3秒倒计时取消/前4.5秒边界/无触发/提前停止；export不带UI。高帧率外拍记录动作→效果P95目标≤350ms。
- [ ] Commit `feat: orchestrate six-second show off capture`。

## T16：片段存储、恢复与空间不足

**依赖：** T12/T14/T15。**Files：** Create `Clips/ClipStore.swift`、`Tests/iOS/ClipStoreTests.swift`；Modify `CaptureCoordinator.swift`。

**Interfaces：** `ClipStore.commit(tempURL:URL,report:ClipReport) throws -> ClipRecord`、`latestRecoverable()->ClipRecord?`、`acquire(_ id:UUID)/release(_ id:UUID)`、`prune(now:Date) throws`。ClipRecord含id/url/createdAt/duration/interrupted，持久JSON采用原子写。

- [ ] 写 `testInvalidClipNeverCommitted`、`testOutOfSpacePreservesLastGoodClip`、`testCrashPartialIsCleanedOnLaunch`。
- [ ] 实现.partial→验证→原子移动；最多最近10个、7天清理；当前播放/分享acquire保护，过期清理不删除使用中资源。
- [ ] 写 `testShareLeasePreventsPrune`、`testLaunchOffersLatestUnfinishedReview`；恢复对话允许继续保存/删除，不自动打开相册或分享。
- [ ] 磁盘容量检测只是预检，仍捕获writer/文件IO错误；以故障注入验证报错后可重拍。
- [ ] Commit `feat: preserve and recover local clips safely`。

## T17：回放、保存与系统分享

**依赖：** T10/T16。**Files：** Create `Clips/ClipReviewView.swift`、`PhotoSaver.swift`、`SharePresenter.swift`、`Settings/PermissionCoordinator.swift`、`Tests/iOS/ClipSharingTests.swift`；Modify Info.plist本地化说明。

**Interfaces：** `PhotoSaver.save(url:URL) async throws`；`SharePresenter.present(url:URL)`；`PermissionCoordinator.cameraStatus()`、`requestCamera() async`、`requestPhotoAdd() async`，status enum覆盖authorized/notDetermined/denied/restricted。

- [ ] 写 `testPhotoDeniedStillAllowsSystemShare`、`testCameraDeniedStillAllowsWatchPractice`、`testShareCancellationKeepsReview`。
- [ ] 实现AVPlayer回放与原生系统分享URL；仅点保存请求PhotoKit addOnly，成功后显示“已保存”，不请求readWrite。
- [ ] 保存按钮连点不产生多条照片资产，失败保留片段；系统分享completion之后释放ClipStore lease，不能弹出即释放。
- [ ] 中文/英文权限文案与用途匹配：相机显示现实画面、Motion识别挥腕、Photos保存短片。系统拒绝界面使用x9黑底，不伪造相机照片。
- [ ] iPhone真机验证第一次允许/拒绝/设置返回、分享取消/完成，系统权限不以Mock结果冒充真机证据。
- [ ] Commit `feat: review save and share magic clips`。

## T18：生命周期、断连与错误恢复收口

**依赖：** T09/T11/T15–T17。**Files：** Create `Session/RecoveryPolicy.swift`、`Entry/RecoveryView.swift`、`Tests/iOS/RecoveryFlowTests.swift`；Modify `AppModel.swift`、`WatchCastModel.swift`。

**Interfaces：** `RecoveryPolicy.transition(error:AppFailure,phase:CaptureState)->RecoveryAction`；AppFailure覆盖linkLost/trackingLost/cameraDenied/diskFull/writerFailed/audioFailed/thermal/background；RecoveryAction描述pause/retry/shareSilent/returnToPractice，不吞错误。

- [ ] 表驱动测试：每个CaptureState × 后台/断连/相机中断，断言新cast禁止、许可撤销、资源释放、界面出口可达。
- [ ] `testForegroundReturnDoesNotAutoResume`、`testOldAckAfterReconnectIgnored`、`testAudioFailureOffersExplicitSilentExport`、`testSeriousThermalStopsSession`。
- [ ] 未知错误提示可操作的重试/退出并记本地日志；不得显示内部堆栈给用户；AR中断与Motion不可用各有独立文字。
- [ ] 跟踪手机idleTimer override只在有效拍摄/舞台期间开启，离开时恢复；低电量提示不阻塞本地练习，但serious/critical热状态暂停。
- [ ] 真机切后台/锁屏/蓝牙范围离开每路径至少3次；Commit `fix: make casting interruptions recoverable`。

## T19：无障碍与大字适配

**依赖：** T08–T18。**Files：** Modify 所有View、`Resources/Localizable.xcstrings`；Create `Tests/UITests/AccessibilityFlowTests.swift`、`Evidence/visual/accessibility.md`。

**Interfaces：** Consumes DESIGN §4/12；Produces所有交互 accessibilityIdentifier、localized label/value/hint；reduceMotion由system OR app派生。

- [ ] UI测试VoiceOver替代施法入口遵循permit，不绕过cutoff；charge仅25/50/75/100%语音变化；装饰法术图从可访问树隐藏。
- [ ] 375×667最大Dynamic Type、两Watch尺寸最大字号检查无关键截断，按钮至少44pt；必要时滚动，不能缩小文字绕过。
- [ ] 静音/关触感仍有视觉就绪反馈；色盲状态不只靠红绿/金色；减少动态下无连续闪烁和大幅缩放。
- [ ] Accessibility Inspector与真实VoiceOver走完整练习→拍摄→分享；未通过阻塞发布。
- [ ] Commit `feat: make wrist magic accessible across sizes`。

## T20：性能、功耗与稳定性门禁

**依赖：** T18/T19。**Files：** Create `Evidence/performance/README.md`、`scripts/verify-session.sh`；Modify具体热点实现，不做无证据重构。

**Interfaces：** 记录单机os_signpost区间motionDecision/hapticDispatch/transportRTT/render/append/mix，日志不可记录用户影像原始内容。

- [ ] Instruments分别测Watch/iPhone，至少100次触发、10段录像、10分钟练习；P50/P95/max、drop ratio、热状态与内存都记录。
- [ ] 校验DESIGN §12各数值；没有能测单程的同步方法时只报告RTT与外拍端到端，不编造精度。
- [ ] 修复确切瓶颈，优先减少分配/粒子/overdraw；writer队列上限3、没有无限重试、没有stale event保留泄漏。
- [ ] 相同场景复测，保留前后对比；如果仍不通过，文档明确实验版限制，不将指标从验收表删除。
- [ ] Commit `perf: verify casting and capture budgets`。

## T21：视觉一致性与完整验收矩阵

**依赖：** T19/T20。**Files：** Create `Evidence/visual/matrix.csv`、`review.md`；Modify已发现偏差的组件和页面。

**Interfaces：** Consumes定稿x4/x5/x8/x9和DESIGN屏幕ID；Produces每个ID的基线/实现截图/差异记录/结论，截图从App获取，不用生成图冒充。

- [ ] 逐页覆盖W01–08、I01–15；主屏、录制、回放、权限、暂停在紧凑与标准手机、两Watch尺寸截图。
- [ ] 对比同一viewport与state：字体、CTA层级、边距、法术占比、safe area、camera scrim、设置组件。记录HIG调整与原型差异及原因，不做像素盲抄。
- [ ] 确认Fireball/Lightning/Force Push美术区分与主控件一致；倒计时无特效；拒绝相机无画面；连接Badge不能仅用isReachable驱动。
- [ ] 阻塞缺陷：关键文字不可读、动作不可达、误导成功、导出含UI、重复cast、可复现崩溃。全部归零；美术微差需逐条记录接受理由。
- [ ] Commit `design: verify native visual and interaction consistency`。

## T22：交付与安装复现

**依赖：** 全部。**Files：** Create `README.md`、`INSTALL.md`、`RELEASE-CHECKLIST.md`、`Evidence/INDEX.md`；归档Xcode工程和示例成片。

**Interfaces：** Produces可复现源码、环境锁定说明、签名步骤、真实三术样片、测试证据索引；不包含私钥、provisioning秘密、用户设备序列号公开清单。

- [ ] 从干净checkout运行core/iOS/Watch测试并构建Release；实际`xcodebuild -showdestinations`选择UDID，禁止在说明里编造设备标识。
- [ ] 按INSTALL从零安装双端，验证打开Watch、离线练习、连接iPhone、Reality与Show Off、照片保存和分享。
- [ ] 安装说明区分Personal Team周期重签与公开分发资格，不承诺无开发账号就可永久分发。
- [ ] 汇总DESIGN每项到任务/测试/证据路径，写真实剩余限制；失败与未测试显式列出，零造假完成项。
- [ ] Commit `docs: deliver verified wrist magic native build`。是否推送/上架另按用户授权处理；不自动发布App Store。

## 2. 覆盖与验收追踪

| 需求 | 实现任务 | 最小证据 |
|---|---|---|
| 三术/选术/蓄力 | T03/T04/T09 | 核心测试+Watch三术录屏 |
| 左右腕/误触发 | T02/T04 | 保留集分母和负例统计 |
| 前台/触感/声音 | T09/T14/T18 | 真机演示+关闭选项 |
| 连接/去重/许可 | T05/T06 | 异常网络序列测试+100次RTT |
| 连接/教学/首页 | T10 | x5对应截图 |
| Reality | T11/T13 | 世界锚和三种效果视频 |
| Show Off | T07/T12/T15 | 三术6秒导出，无UI |
| 音效 | T14 | cue时间测量、静音片段 |
| 保存/分享/权限 | T16/T17 | Photos拒绝仍可分享，故障注入 |
| 断连/锁屏/恢复 | T18 | 状态×中断矩阵 |
| 设计/组件 | T08/T21 | token与逐页对比 |
| 无障碍 | T19 | 大字/VoiceOver/Reduce Motion |
| 性能与功耗 | T20 | Instruments与外拍样片 |
| 安装复现 | T01/T22 | 真机双端、环境与签名说明 |

## 3. 三道研发决策门

**Gate A（T02/T04）动作确实可玩：** 若门槛未达到，先修姿态校准和门控。不能在UI完成后把动作换成无解释点击并宣称原需求完成。

**Gate B（T06）反馈足够及时：** 在真实设备记录连接状态变化和时延；越过上限时Reality与Show Off保留为未通过，不藏在偶发网络解释里。

**Gate C（T07/T12）特效真正进入成片：** 无UI录像、方向、时长、编码、背压全过。snapshot/原始视频不等价，不应只凭预览通过。

## 4. 本轮计划自审

- 范围：保留三术和双模式，固定构图/无现场录音等新增取舍明确标为工程建议。
- 平台：不虚构手掌识别、后台保活与Haptic力度；新旧编码API封装版本边界。
- 时间：iPhone本地录制时钟、Watch本地RTT，跨设备不比较绝对时间。
- 状态：倒计时无效果，首帧起算；过期与重复、恢复旧包、晚施法都有归属任务。
- 文件：所有主要type有定义任务；EffectCue在T07探针使用时即遵循T13契约；UI tokens单源。
- 证据：每个真机门禁有设备/命令/样本；所有checkbox保持未完成，未把文档写成已实现报告。

## 5. 执行交接

请先审阅 DESIGN.md 的新增工程取舍与本计划。建议 **Native/inline 执行**：由主Agent按任务推进，因共享状态机、许可协议和渲染时间线紧密耦合，顺序推进便于核对接口。若用户明确选择子代理方案，再按 Superpowers 对每项实现与review组织子代理；本轮未启动任何子代理。

执行开始读取 superpowers:executing-plans；如果选择子代理则读取 superpowers:subagent-driven-development。从T01开始，遇到硬件/平台阻塞先做可完成的纯逻辑与文档，明确阻塞依赖，不假称真机完成。
