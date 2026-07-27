# AFU-WL 体脂秤 iOS 客户端

一个使用 SwiftUI 和 CoreBluetooth 编写的非官方客户端，用于在不注册厂商账号、不连接厂商服务器的情况下读取特定 AFU-WL / Welland 体脂秤，并可选择写入 Apple 健康。

> 本项目来自社区逆向研究，与蚂蚁阿福、沃莱、Fitdays、Icomon 或 Apple 没有隶属或授权关系。

本修改版基于 [maoziban/smart-body-scale-IOS](https://github.com/maoziban/smart-body-scale-IOS) 开发，并保留了原仓库的 Git 提交历史。新增内容包括 HealthKit 写入、ADC 选择、与 CLI 一致的广播解析、设备身份绑定、算法与隐私说明等。

## 当前功能

- 扫描并连接 `AFU-WL-TZ-A1`、`subtype=7` 的已验证设备；
- 实时显示体重，稳定后保存一条本地记录；
- 保留秤发送的两个 ADC，并允许选择用于估算的 ADC 1 或 ADC 2；
- 根据体重和阻抗估算体脂，并展示由体脂按比例推算的其他指标；
- 本人资料、家庭成员匹配和本地历史；
- 可选写入 Apple 健康：
  - 体重；
  - BMI；
  - 体脂率；
  - 去脂体重；
- 不包含账号、广告、网络请求或第三方统计 SDK。

## 数据分别来自哪里

| 数据 | 来源 | 含义 |
|---|---|---|
| 体重 | 秤直接测量 | BLE 包解析结果 |
| ADC 1 / ADC 2 | 秤直接发送 | 物理含义尚未完全确认 |
| 阻抗 | 协议换算 | 从所选 ADC 得到 |
| BMI | 本地计算 | 体重 ÷ 身高² |
| 体脂率 | 本地 BIA 公式估算 | 不是秤返回的官方体脂字段 |
| 水分、肌肉、骨量、蛋白质、皮下脂肪 | 本地粗略推算 | 不能视为独立测量 |

消费级四电极体脂秤适合观察同一条件下的长期趋势，不应替代医疗检查。当前 BIA 主公式参考 Segal 等人在 1988 年发表的人体成分估算公式；其研究人群主要为成人，因此儿童和青少年的结果尤其需要谨慎解读。没有有效阻抗时使用基于 BMI、年龄和性别的回退估算。

公式来源：

- Segal KR et al. (1988), [Lean body mass estimation by bioelectrical impedance analysis: a four-site cross-validation study](https://pubmed.ncbi.nlm.nih.gov/3337041/)
- Deurenberg P et al. (1991), [Body mass index as a measure of body fatness: age- and sex-specific prediction formulas](https://doi.org/10.1079/BJN19910073)

## 已验证硬件

- 广播名称：`AFU-WL-TZ-A1`
- category：`2`
- subtype：`7`
- 服务：`FFB0`
- Notify 特征：`FFB2`

其他型号和固件可能使用不同广播或数据格式。详细逆向记录见 [PROTOCOL.md](PROTOCOL.md)。

## 环境要求

- Xcode 16 或更高版本；
- iOS / iPadOS 16.6 或更高版本；
- 支持蓝牙低功耗的实体 iPhone 或 iPad；
- 写入 Apple 健康需要在个人开发团队或正式团队中启用 HealthKit。

模拟器可以用于编译和检查界面，但不能完成真实蓝牙测量。

## 运行

1. 克隆仓库并打开 `体脂秤.xcodeproj`。
2. 选择 App Target，在 **Signing & Capabilities** 中选择自己的 Team。
3. 如有需要，将 Bundle Identifier 改成自己拥有的唯一标识。
4. 连接 iPhone 或 iPad并运行。
5. 完全退出厂商 App 和电脑端 CLI，避免它们占用蓝牙连接。
6. 光脚站上秤将其唤醒，在配对页选择发现的设备。

如果秤无法出现，请依次确认：

- 系统设置中已允许本 App 使用蓝牙；
- 厂商 App、另一台手机和电脑端 CLI 均未连接；
- 秤已经亮屏并靠近设备；
- 广播名称和 subtype 与上面的已验证设备一致。

## Apple 健康

在“我的资料 → Apple 健康”中启用同步并选择指标。App 只自动写入归属于“本人”的新实时测量，不会批量上传旧历史或家庭成员记录。

体重属于直接测量；BMI、体脂率和去脂体重包含本地公式计算。HealthKit 样本会携带算法版本、阻抗和 ADC 编号等元数据，用于之后追溯。

## 隐私

App 本身不发起网络请求，资料和历史保存在 App 沙盒中。启用 Apple 健康后，所选数据会交给 HealthKit，是否通过 iCloud 同步由用户的系统设置决定。完整说明见 [PRIVACY.md](PRIVACY.md)。

公开 Issue 或日志前，请删除姓名、出生日期、体重和蓝牙设备标识等个人信息。

## 项目结构

```text
体脂秤/
├── ContentView.swift       # SwiftUI、蓝牙协议、模型与算法
├── HealthKitManager.swift  # Apple 健康授权和写入
├── 体脂秤.entitlements      # HealthKit entitlement
└── Assets.xcassets
```

当前代码仍以小型原型结构为主。后续适合继续拆分蓝牙、协议、算法、存储和界面模块，并为协议解析与测量会话增加独立测试 Target。

## 构建检查

```bash
xcodebuild \
  -project "体脂秤.xcodeproj" \
  -scheme "体脂秤" \
  -destination "generic/platform=iOS Simulator" \
  CODE_SIGNING_ALLOWED=NO \
  build
```

GitHub Actions 会在 Push 和 Pull Request 时执行相同的无签名构建。

## 贡献

欢迎提交兼容性修复和脱敏后的协议样本。请避免：

- 把真实健康数据、设备 UUID 或 Apple 开发团队信息提交到仓库；
- 把估算指标描述成医疗测量；
- 在没有对照数据时修改生产公式或默认 ADC。

## 开源许可

截至 2026-07-27，上游仓库没有提供 `LICENSE`。公开可见不等于允许复制、修改或重新分发，因此当前修改版也不能单方面给上游代码添加新的开源许可证。

在公开发布或接受外部贡献前，应先取得上游作者的明确授权，或由上游作者添加开源许可证。获得授权后，本仓库会保留原作者署名，并按照上游许可证的要求发布。
