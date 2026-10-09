# 在 Mac mini 上继续开发

当前代码和验证进度见 [开发进度](docs/IMPLEMENTATION-STATUS.md)。真机验证尚未进行；模拟器构建通过不代表传感器、双端无线链路或相机效果已实测。

## 打开项目

1. 克隆仓库并进入代码所在分支；最终交付前的集成分支是 `feat/native-mvp`。
2. 安装完整 Xcode 和 iOS、watchOS 模拟器运行时。已验证的 CI 工具链是 Xcode 16.4 / Swift 6；最低部署版本是 iOS 17、watchOS 10。
3. 打开 `WristMagic.xcodeproj`。工程已提交，无需安装工程生成器或第三方运行时依赖。
4. iPhone 选择 `WristMagic-iOS`；Watch 选择 `WristMagic-Watch`。测试方案为 `WristMagic-iOSTests` 与 `WristMagic-WatchTests`。

```bash
git clone https://github.com/geekjourneyx/wrist-magic.git
cd wrist-magic
git switch feat/native-mvp
open WristMagic.xcodeproj
```

## 自动化验证

```bash
xcodebuild -version
python3 scripts/check-project.py
scripts/test-core.sh
xcrun simctl list devices available
```

将实际可用的设备 UDID 填入环境变量，测试脚本会生成独立 `.xcresult`，保存在 `Evidence/test-results/`：

```bash
IOS_SIMULATOR_UDID='<iPhone simulator UDID>' scripts/test-ios.sh
WATCH_SIMULATOR_UDID='<Apple Watch simulator UDID>' scripts/test-watch.sh
```

无签名编译：

```bash
xcodebuild -project WristMagic.xcodeproj -scheme WristMagic-iOS -configuration Release -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -project WristMagic.xcodeproj -scheme WristMagic-Watch -configuration Release -destination 'generic/platform=watchOS Simulator' CODE_SIGNING_ALLOWED=NO build
```

修改工程源文件清单后运行 `python3 scripts/generate-project.py`，再运行结构检查。不要只修改生成后的工程而遗漏生成脚本。

## 真机签名和首次运行

在 Xcode 的 Signing & Capabilities 为两个应用目标选择自己的开发团队。默认 bundle ID 是 `io.github.geekjourneyx.wristmagic` 与 `.watchkitapp`；如需更改，需同步更新伴随应用标识和工程生成脚本。连接已配对的 iPhone 与 Apple Watch，选择真实运行目标并根据系统要求启用开发者模式。

手机和手表应用均保持前台。先验证 Watch 独立练习，再连接手机舞台。应用仅请求相机和添加照片所需权限，不使用麦克风、HealthKit、workout 或后台动作队列。

左右腕动作识别、AR 跟踪、实际成片、音画同步、断连恢复、热状态和功耗等实测项目必须逐项补齐后才能做发布判断。当前动作 profile 是实验参数，不代表已训练或已达到识别率目标。
