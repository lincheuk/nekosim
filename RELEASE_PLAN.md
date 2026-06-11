# NekoSim 上线工作流（Release Plan）

从当前状态（功能 ~85%，仅 debug 包）到公开可用的完整路径。
按阶段推进，每个阶段有明确的完成判据（Exit Criteria）。

---

## 阶段 0 — 仓库与基线（0.5 天）

| 事项 | 说明 |
| --- | --- |
| git 仓库化 | 当前是解压目录，先 `git init` + 初始 commit，之后所有改动可追溯 |
| 分支模型 | `main`（可发布）+ `dev`（日常），上线前只从 main 出包 |
| 版本规范 | `pubspec.yaml` 的 `version: x.y.z+build`，每次发版 build 自增 |

**Exit**: 仓库有干净的 main 分支，CI 能拉起。

## 阶段 1 — 应用身份（1~2 天）

| 事项 | 说明 |
| --- | --- |
| applicationId | `ee.nekoko.nlpa2.open` → 自有域名反写（如 `app.nekosim.xxx`）。涉及：`android/app/build.gradle.kts` 的 applicationId / namespace、`AndroidManifest.xml` package、Kotlin 包目录、iOS bundle id、`LocalNotificationService` 里的 Windows appUserModelId/guid |
| OTBridge / NBridge 联动 | 包名改掉后 `ee.nekoko.nbridge.provider` 查询与 OMAPI ARA-M 路径要重新真机验证（这是当初保留包名的原因，改完必须回归） |
| 应用名 / 图标 | BRANDING.md 限制：Nekoko 猫吉祥物**不能**用作自己的 logo/图标。需要全新图标（android mipmap 全密度 + iOS AppIcon + Windows ico + web favicon），`flutter_launcher_icons` 一次生成 |
| 上游署名 | MIT 许可：保留 LICENSE/NOTICE，在"关于"页注明 based on NekokoLPA2 |

**Exit**: 新包名 + 新图标的 debug 包在真机安装，OTBridge 路径回归通过。

## 阶段 2 — 签名与构建工程（1 天）

| 事项 | 说明 |
| --- | --- |
| Android keystore | `keytool -genkeypair` 生成 release keystore；`android/key.properties`（不入库，.gitignore）；`build.gradle.kts` 配 signingConfigs.release |
| 混淆 | `--obfuscate --split-debug-info=build/symbols`，符号表归档 |
| 出包矩阵 | `flutter build apk --release --flavor community --split-per-abi`（GitHub Release）+ `appbundle`（Play）|
| CI | GitHub Actions：push → analyze + test；tag → 出包 + 上传 Release。仓库 secrets 存 keystore base64 |

**Exit**: `flutter build appbundle --release` 一条命令出可上传包；CI 绿。

## 阶段 3 — 安全与数据完整性（2~3 天）

| 事项 | 说明 |
| --- | --- |
| 密钥安全存储 | SMTP 密码 / bot token / 云 API key 从 SharedPreferences 明文迁到 `flutter_secure_storage`（含旧数据一次性迁移） |
| 传输安全 | 云端 serverUrl 强制 https（允许用户显式豁免局域网 http） |
| 备份完整性 | `DatabaseService.importDatabase/resetDatabase` 表清单补 `nekosim_assets`（已知 bug） |
| 权限最小化 | 复查 Manifest 权限是否都有真实用途，Play 数据安全表单按实际填写 |

**Exit**: 抓包确认无明文密钥外泄；导出→重置→导入全量数据无损。

## 阶段 4 — 质量门槛（3~5 天，可与 3 并行）

| 事项 | 说明 |
| --- | --- |
| 单元测试 | 纯函数优先：CSV/JSON 导入导出 round-trip、`parseLpa`、locale 分流（zh-Hans/zh-Hant/HK/MO）、`reminderId` 稳定性、`cleanApiKey` |
| Widget 测试 | 资产页筛选/排序/搜索、编辑页保存、LPA 对话框解析预览 |
| 提醒可靠性 | 真机矩阵：原生 Android / MIUI / ColorOS / HarmonyOS NEXT 杀后台后提醒是否到达；电池优化白名单引导页 |
| 提醒功能补齐 | 本地提醒对齐云端的"提前 N 天"；iOS 64 条 pending 上限做滚动窗口（最近 50 条 + 启动时补排） |
| 多语言走查 | 9 语言全页面截图走查（重点 zh/zh-Hant 分流、长文案截断） |
| 崩溃上报 | 接 Sentry（自托管可选）或 Firebase Crashlytics，release 包默认开 |

**Exit**: `flutter test` 全绿；4 台真机矩阵提醒到达率 100%；崩溃上报后台能看到事件。

## 阶段 5 — 合规与商店材料（2 天，可与 4 并行）

| 事项 | 说明 |
| --- | --- |
| 隐私政策 | 必须项（云提醒上传手机号/邮箱凭据）。静态页托管，App 内"关于"和商店链接都指向它 |
| 商店素材 | 截图（手机+平板）、feature graphic、短/长描述（至少 en/zh 双语） |
| 内容分级 | Play 问卷 + App Store 年龄分级 |
| SimJiang 服务器 | server.py 入仓或独立仓库，配 Dockerfile + compose；文档写清自托管步骤（用户自己的服务器自己负责） |

**Exit**: 隐私政策可访问；商店后台草稿填完可提交。

## 阶段 6 — 灰度与发布（1 周日历时间）

1. **内测**: GitHub pre-release + Play internal testing，自用 3~5 天
2. **公测**: Play open testing / TestFlight，盯崩溃率（目标 crash-free > 99.5%）
3. **正式**: Play 分阶段发布（10% → 50% → 100%），GitHub Release 同步 tag
4. **回滚预案**: 保留上一版 aab；服务端协议向后兼容（payload 加版本号字段）

**Exit**: 商店上架 + GitHub Release 可下载，崩溃率达标。

---

## 总时间线

```text
周 1     阶段 0-2（身份、签名、CI）
周 2     阶段 3-4（安全、测试、提醒可靠性）
周 2-3   阶段 5（合规材料，与周 2 并行）
周 3-4   阶段 6（灰度 → 正式）
```

集中开发约 **2 周工程量 + 1~2 周灰度日历时间**。

## 当前已完成（截至本文档创建）

- 功能：资产 CRUD、Profile 双向关联、卡片插件管线、云提醒（SimJiang 协议）、
  本地提醒（zonedSchedule + 重启恢复）、导入导出（含 SimJiang 兼容）、
  搜索/筛选/排序、QR/图片/粘贴导入 LPA、9 语言
- 修复：简中误判繁中（宿主 locale 解析）、remind天 payload key、CSV 多行字段
- 工程：本机 Flutter 3.44.1 全链路（analyze → test → APK）可用
