# 走遍中国（TravelChina Footprint）

> 中国地级市足迹地图 · HarmonyOS 6 / 7 原生应用
> 记录你去过的每一个市州级行政区，去过的点亮，没去过的保持暗色。

![version](https://img.shields.io/badge/version-1.0.0-F5C542)
![platform](https://img.shields.io/badge/HarmonyOS-6%20%2F%207-22D3EE)
![license](https://img.shields.io/badge/license-All%20rights%20reserved-8A99B5)

**应用名**：走遍中国 ｜ **包名**：`com.TravelChina.footprint`
**已上线的 AGC 配置**：项目「走遍中国」→ APP ID `6917616282702892254` → 开放能力「地图服务」已开启，调试 Profile「走遍中国调试」有效期至 2027-09-13。

**当前版本**：`v1.0.0`（versionCode `1000000`，2026-09-14）— 详见 [CHANGELOG.md](CHANGELOG.md)

**上架资料**（华为应用市场）：

- [上架发布指南](docs/上架发布指南.md)：官方流程 21 步、备案与版权证书要求、合规自检表
- [隐私政策](docs/隐私政策.md) ｜ [可托管的 HTML 版](docs/privacy-policy.html)
- [应用市场素材](docs/应用市场素材.md)：商店文案、权限说明、隐私标签、截图清单

**隐私政策公网网址**（已用 GitHub Pages 托管，可直接填进 AGC）：
<https://anqilike.github.io/TravelChinaFootprint/privacy-policy.html>

---

## 一、当前状态

| 项目 | 状态 |
|---|---|
| 工程编译 | ✅ 已通过（`hvigor assembleHap` → BUILD SUCCESSFUL） |
| 构建产物 | `entry/build/default/outputs/default/entry-default-signed.hap` |
| 点亮单元 | ✅ 370 个（真实行政区划数据，GCJ-02 坐标） |
| 地图能力 | ✅ 华为 Map Kit 点位方案（`@kit.MapKit`） |
| 本地存储 | ✅ relationalStore（RDB），含索引与事务 |
| 数据校验 | ✅ 7/7 真实地标坐标反查通过 |
| 真机运行 | ✅ Mate 80（HarmonyOS 7.0.0 / API 26）实测通过 |
| 沉浸光感 | ✅ 底部页签栏走系统材质（`barFloatingStyle`），实测有模糊折射；鸿蒙 6 自动降级 |
| 隐私合规 | ✅ 首次启动同意弹层 + 应用内隐私政策 + 一键清除本机数据 |

---

## 二、环境要求

> **关于签名**：`build-profile.json5` 里带的是一份**本机调试签名**配置
> （密码为 DevEco 加密串，且 `.p12` / `.cer` / `.p7b` 本身不在仓库里）。
> 换一台机器编译时，请用 DevEco Studio 的
> `File → Project Structure → Signing Configs → Automatically generate signature`
> 生成你自己的签名；`.gitignore` 已排除所有签名材料文件。

- **DevEco Studio**：26.0.0（本机路径 `E:\DevEco26\DevEco Studio`）
- **HarmonyOS SDK**：26.0.0（API 26），随 DevEco Studio 安装
- **目标设备**：HarmonyOS 5.0.0(12) 及以上（`compatibleSdkVersion = 5.0.0(12)`，`targetSdkVersion = 26.0.0`）
- **沉浸光感最低要求**：HarmonyOS 7（API 26）；鸿蒙 6 及更早自动退回常规毛玻璃

### 用 DevEco Studio 打开

直接用 DevEco Studio 打开本目录：`D:\China\TravelChinaFootprint`

### 用命令行编译（已验证可用）

```powershell
$env:PATH = "E:\DevEco26\DevEco Studio\jbr\bin;E:\DevEco26\DevEco Studio\tools\node;" + $env:PATH
$env:NODE_HOME = "E:\DevEco26\DevEco Studio\tools\node"
$env:DEVECO_SDK_HOME = "E:\DevEco26\DevEco Studio\sdk"
Set-Location D:\China\TravelChinaFootprint
& "E:\DevEco26\DevEco Studio\tools\hvigor\bin\hvigorw.bat" assembleHap --no-daemon
```

> 两个必须先设的环境变量说明：
> - `jbr\bin` 放进 PATH：打包阶段需要 Java，否则报 `spawn java ENOENT`；
> - `tools\node` 放进 PATH 的最前面：hvigor 会用它自带的 npm 安装依赖，用错 Node 会报 `npm.cmd is not recognized`。

---

## 三、第一次运行前必须做的两步

### 第 1 步：开通华为地图服务（不做这一步，地图是空白的）

1. 注册/登录华为开发者账号并完成实名认证；
2. 在 AppGallery Connect 创建项目与应用，**包名填 `com.TravelChina.footprint`**；
3. 开通"地图服务"开放能力（二选一）：
   - DevEco Studio：`File → Project Structure → Signing Configs → Enable open capabilities → 勾选 Map Kit → OK → Apply`；
   - AGC 网站：`开发与服务 → 选择应用 → 开放能力管理 → 打开"地图服务"开关`；
4. 在 AGC **协议签署记录**中签署《华为地图服务使用协议》；
5. **顺序很重要**：申请调试证书 → 注册调试设备 → 开启地图服务 → **重新申请调试 Profile** → 手动签名。
   Profile 如果在开通地图服务之前申请，地图不会显示。

> 从 HarmonyOS 5.0.2(14) 起**不需要**再配置公钥指纹和 Client ID，网上老教程可以跳过。

### 第 2 步：配置签名

DevEco Studio：`File → Project Structure → Signing Configs → 勾选 Automatically generate signature`，用你的华为账号自动生成调试签名。

完成后即可用真机运行。**模拟器不支持"我的位置"、离线地图等功能，地图相关验证请用真机。**

---

## 四、工程结构

```
TravelChinaFootprint/
├── AppScope/                                  应用级配置（包名、版本、图标）
├── entry/src/main/
│   ├── module.json5                           模块配置 + 权限声明
│   ├── ets/
│   │   ├── entryability/EntryAbility.ets      入口 Ability（默认暗色主题）
│   │   ├── entrybackupability/                备份扩展
│   │   ├── pages/Index.ets                    主框架：4 个 Tab + 启动引导
│   │   ├── view/
│   │   │   ├── MapPage.ets                    足迹地图（Map Kit + 370 点位）
│   │   │   ├── CityListPage.ets               足迹清单（搜索 / 点亮 / 取消）
│   │   │   ├── StatsPage.ets                  统计与成就
│   │   │   └── SettingsPage.ets               我的 / 设置 / 数据导出
│   │   ├── viewmodel/
│   │   │   ├── FootprintStore.ets             全局状态（状态管理 V2）
│   │   │   └── AchievementEngine.ets          成就计算
│   │   ├── repository/
│   │   │   ├── CityRepository.ets             城市字典（rawfile 只读）
│   │   │   ├── DatabaseHelper.ets             RDB 初始化与建表
│   │   │   └── VisitRepository.ets            到访记录读写
│   │   ├── service/
│   │   │   ├── LocationService.ets            定位 → 最近城市
│   │   │   └── ExportService.ets              数据导出（JSON）
│   │   ├── model/                             类型定义
│   │   ├── common/
│   │   │   ├── Theme.ets                      视觉规范常量
│   │   │   ├── MaterialKit.ets                沉浸光感材质（页签栏 THIN + 金色光感反馈）
│   │   │   ├── WindowService.ets              状态栏 / 手势条避让区测量
│   │   │   └── PrivacyConsent.ets             隐私政策同意状态（preferences）
│   │   └── view/PrivacyPolicy.ets             隐私政策全文视图
│   └── resources/
│       ├── base/media/marker_*.png            地图点位图标（脚本生成）
│       └── rawfile/city_dict_v1.json          370 个点亮单元字典
├── docs/                                      上架资料（发布指南 / 隐私政策 / 商店素材）
├── CHANGELOG.md                               版本记录
└── entry/build/...                            构建产物（含 HAP）
```

---

## 五、已实现功能（对照《设计前指导书》）

| 编号 | 功能 | 对应章节 | 状态 |
|---|---|---|---|
| F-01 | 地图全图渲染（暗色底 + 明暗两种点位） | 2.2 | ✅ |
| F-02 | 点亮 / 取消点亮（含落库与撤销提示） | 2.2 | ✅ |
| F-03 | 定位识别当前城市（最近城市判定 + 权限降级） | 2.2 | ✅ |
| F-04 | 统计与覆盖率（数量、省份覆盖、进度条） | 2.2 | ✅ |
| F-05 | 数据导出（JSON，可携带） | 2.2 | ✅ |
| P-02 | 足迹地图页 | 3.3 | ✅ |
| P-03 | 城市气泡（半模态详情） | 3.3 | ✅ |
| P-07 | 足迹清单（已点亮/未点亮 + 搜索） | 3.3 | ✅ |
| P-08 | 统计与成就（8 个徽章） | 3.3 | ✅ |
| P-10 | 我的 / 设置（含地图数据来源与审图号说明） | 3.3 | ✅ |
| P-04 | 城市详情（到访记录时间轴、照片） | 3.3 | ⏳ 待做 |
| P-05 | 打卡表单（标签 + 备注，点亮时一并录入） | 3.3 | ✅ 核心部分 |
| P-06 | 批量点亮（清单页批量模式，含事务写入） | 3.3 | ✅ |
| P-09 | 分享海报 | 3.3 | ⏳ 待做 |
| P-12 | 桌面服务卡片（Form Kit） | 3.3 | ⏳ 待做 |

---

## 六、两个绕不开的设计决策

### 1. 为什么用"点位"而不是"行政区色块"

《设计前指导书》附录 G / 6.1.4 的结论：**自己绘制行政区边界属于"互联网地图编制（编辑加工、格式转换）"，法规要求必须由持测绘资质的单位承担**——这是主体资格问题，不是送审能补正的。

而"在经审核批准的华为底图上叠加标注点"属于法规允许的"增值服务—标注"，配合展示审图号即可合规。所以本工程：

- 底图：华为 Map Kit；
- 点亮表现：金色点位（未点亮为暗色小点）；
- 合规：启动时调用 `setApproveNumberEnabled(true)` 显示审图号，不遮挡地图 Logo。

### 2. 为什么坐标是 GCJ-02

华为地图在中国大陆使用 GCJ-02 坐标系，而本工程的城市字典来自公开行政区划数据（同为 GCJ-02），两者可直接叠加，不需要纠偏。若将来更换为 WGS-84 数据源，必须先用 `map.convertCoordinateSync()` 转换。

---

## 七、数据说明

| 项 | 值 |
|---|---|
| 点亮单元总数 | 370（363 个市州级 + 4 个直辖市 + 香港 + 澳门 + 台湾省） |
| 覆盖省级行政区 | 34 |
| 字典版本 | v1 |
| 坐标系统 | GCJ-02 |
| 数据来源 | 公开行政区划边界数据 + 民政部行政区划代码 |

数据校验脚本（可随时重跑）：

```powershell
node D:\China\_tools\verify_city_dict.mjs
```

重新生成字典与图标：

```powershell
node D:\China\_tools\build_city_dict.mjs
node D:\China\_tools\build_icons.mjs
```

---

## 八、常见问题

| 现象 | 原因与处理 |
|---|---|
| 地图一片空白，只有 Logo 和控件 | ① AGC"地图服务"未开通；② Profile 是在开通服务之前申请的（需重新申请）；③ 未使用手动签名 |
| 编译报 `spawn java ENOENT` | PATH 里加上 `E:\DevEco26\DevEco Studio\jbr\bin` |
| 编译报 `npm.cmd is not recognized` | 把 `E:\DevEco26\DevEco Studio\tools\node` 放到 PATH 最前面 |
| 点位太密看不清 | 全国视野下未点亮城市自动压暗到 0.38；放大到缩放 4.5 以上会自动提亮；也可点右侧 ★ 只看已点亮 |
| 定位无反应 | 需在真机上授权定位权限；模拟器不支持 |
| 安装包未签名 | 需在 DevEco 中配置签名后才可安装到设备 |

---

## 九、后续开发建议（按优先级）

1. **P-06 批量点亮**：出差党刚需，一次点亮整省；
2. **P-05 打卡表单**：标签 / 天数 / 备注，让到访记录有内容；
3. **P-09 分享海报**：传播的核心，用 ArkUI Canvas 离屏绘制（注意：海报若含地图，须原样使用标准地图并标注审图号）；
4. **P-12 服务卡片**：桌面进度卡片，提升打开率；
5. **云同步**：Cloud Foundation Kit，多设备不丢数据。

---

*本工程为个人足迹记录工具，不提供地图搜索、导航等互联网地图服务。*
