# NekoSim

**语言:** **简体中文** | [English](./README_en.md)

NekoSim 是一款跨平台的 SIM / eSIM 卡资产管理应用。

如果你手里有不止一两张卡——实体卡、eSIM、备用卡、出国旅行卡、物联网卡——你大概遇到过这些问题：哪张卡是哪个运营商的？套餐多少钱、还剩多久到期？这张 eSIM profile 当初是从哪买的？NekoSim 把这些信息变成一份随身的卡片台账，并且直接关联到卡片上真实的 eSIM profile，到期前自动提醒你。

## 核心功能

### 卡片资产台账
为你名下每一张 SIM / eSIM 建立档案：运营商、套餐、费用、有效期、购买渠道、备注，完整的增删改查。

### 与真实 Profile 双向关联
台账不是孤立的表格——资产记录可以和设备上实际检测到的 eSIM profile 互相绑定，看到 profile 就知道它的来龙去脉，看到台账就知道卡装在哪。

### 到期提醒
- **本地提醒**：系统级定时通知，重启后依然有效
- **云提醒**（可选）：对接可自托管的 SimJiang 协议服务器，多设备同步提醒

### 灵活导入
- 扫描二维码、识别图片、粘贴激活码，多种方式导入 LPA profile
- 资产数据支持导入导出，备份迁移不丢数据

### 检索与整理
跨运营商、标签、有效期状态的搜索、筛选和排序，卡再多也能马上找到。

### 多语言与统一设计
- 9 种语言：简体中文、繁體中文、English、日本語、한국어、Deutsch、Español、Français、Italiano
- 资产页面与 eSIM 管理界面采用同一套玻璃拟态设计，体验一致

## eSIM 管理核心

NekoSim 的 eSIM 管理能力来自 [NekokoLPA2](https://github.com/iebb/NekokoLPA2)，支持本机 eUICC、外接读卡器和远程读卡器：

| 连接方式 | Android | iOS | macOS | Linux | Windows | Chrome |
| --- | --- | --- | --- | --- | --- | --- |
| BLE 读卡器 | ✅ | ✅ | ✅ | ❌ | ✅ | ✅ |
| USB CCID 读卡器 | ✅ | ✅ | ✅ | ✅ | ✅ | ❌ |
| 远程读卡器 | ✅ | ✅ | ✅ | ✅ | ✅ | ✅ |
| OMAPI | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| Telephony / TMAPI | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| `OTBridge` 提供者 | ✅ | ❌ | ❌ | ❌ | ❌ | ❌ |
| WebUSB SCRP / WebCard | ❌ | ❌ | ❌ | ❌ | ❌ | ✅ |

说明：
- Telephony / TMAPI 与 `OTBridge` 仅限 Android。已 root 的设备可借助 [OTBridge](https://github.com/iebb/OTBridge/releases) 启用 Telephony 支持并绕过 OMAPI ARA-M 限制，NekoSim 本体无需特权安装。
- 资产管理层目前以 Android 为主要开发与测试平台。

## 下载

NekoSim 正在向首个公开版本推进，构建产物将发布在 [Releases](https://github.com/lincheuk/nekosim/releases) 页面。

## 从源码构建

```sh
flutter pub get
flutter build apk --release --flavor community --split-per-abi
```

## 更新日志

见 [CHANGELOG.md](CHANGELOG.md)。

## 反馈

问题、功能建议请提 [GitHub Issues](https://github.com/lincheuk/nekosim/issues)。

## 致谢、商标与许可

NekoSim 是 [NekokoLPA2](https://github.com/iebb/NekokoLPA2)（作者 Nekoko）的独立 fork，与 NekokoLPA 及 SIMLINK LTD 无关联，未获其官方授权、认证或背书。**NekokoLPA 是 SIMLINK LTD 的注册商标**，此处仅用于如实说明本项目的来源与兼容性。NekokoLPA 猫吉祥物（作者 @sanzennami）未用作 NekoSim 的 logo 或品牌标识。详见 [NOTICE](NOTICE) 与 [BRANDING.md](BRANDING.md)。

NekoSim 基于 [MIT 许可证](LICENSE) 发布，保留上游版权声明。
