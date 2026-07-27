# AFU-WL 体脂秤 iOS 客户端

一个使用 SwiftUI 和 CoreBluetooth 编写的非官方客户端，用于在不连接阿里服务器的情况下读取特定 AFU-WL / Welland 体脂秤，并可选择写入 Apple 健康。

> 本项目来自社区逆向研究，与蚂蚁阿福、沃莱、Fitdays、Icomon 或 Apple 没有隶属或授权关系。

本修改版基于 [maoziban/smart-body-scale-IOS](https://github.com/maoziban/smart-body-scale-IOS) 开发，并保留了原仓库的 Git 提交历史。新增内容包括 HealthKit 写入、ADC 选择、更稳定的广播解析、设备身份绑定、算法与隐私说明等。

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

当前 BIA 主公式参考 Segal 等人在 1988 年发表的人体成分估算公式；其研究人群主要为成人，因此儿童和青少年的结果尤其需要谨慎解读。没有有效阻抗时使用基于 BMI、年龄和性别的回退估算。

公式来源：

- Segal KR et al. (1988), [Lean body mass estimation by bioelectrical impedance analysis: a four-site cross-validation study](https://pubmed.ncbi.nlm.nih.gov/3337041/)
- Deurenberg P et al. (1991), [Body mass index as a measure of body fatness: age- and sex-specific prediction formulas](https://doi.org/10.1079/BJN19910073)

## 误差与限制

体重为秤直接测量，ADC 为秤直接发送；阻抗来自协议换算。体脂、水分、肌肉、骨量等身体成分均为本地公式估算，不应替代医疗检查。

蚂蚁阿福的身体成分结果同样属于消费级估算。可切换 ADC 1 和 ADC 2 来缩小与官方结果的差距，但“更接近官方结果”不代表“医学上更准确”（不过仍建议选择差距较小的 ADC，阿里的结果有可能更接近真实数据）。

观察长期趋势时，建议固定使用同一个 ADC，并保持相似的测量条件。

## 已验证硬件

- 广播名称：`AFU-WL-TZ-A1`
- category：`2`
- subtype：`7`
- 服务：`FFB0`
- Notify 特征：`FFB2`

其他型号和固件可能使用不同广播或数据格式。详细逆向记录见 [协议笔记](PROTOCOL.md)。

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
5. 完全退出其他设备上的蚂蚁阿福；如果秤仍被占用，可以关闭那些设备的蓝牙。不要关闭正在运行本 App 的 iPhone/iPad 蓝牙。
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
├── App/                    # App 入口与根界面
├── Bluetooth/              # BLE 扫描、连接、测量状态机与协议解析
├── Domain/                 # 数据模型、用户资料与身体指标算法
├── Features/               # 测量、历史、配对、资料等 SwiftUI 页面
├── Health/                 # Apple 健康授权和写入
├── Assets.xcassets/        # 图标与颜色资源
└── 体脂秤.entitlements      # HealthKit entitlement
docs/
└── PROTOCOL.md             # AFU-WL 协议逆向笔记
```

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

## 许可证

本修改版已取得上游作者授权，并按照 [GNU General Public License v3.0](LICENSE) 发布。
