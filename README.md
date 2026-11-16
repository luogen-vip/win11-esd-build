# win11-esd-build

在 GitHub Actions 云端构建 Windows 11 26H2（26300.10066）简体中文专业版 `install.esd`。

- 构建源：UUP dump（`0344497f-5f08-49b5-9eae-6adf91923a2e`）
- 版本：26300.10066 / amd64 / zh-cn / Professional
- 配置：`ConvertConfig.ini`
  - `AddUpdates = 1`  集成微软该版本内置的最新累积更新
  - `wim2esd = 1`     实心 ESD 压缩
  - `SkipISO = 1`     不生成 ISO，只输出 `install.esd`
  - `Cleanup = 0`     不做组件清理
  - `NetFx3 = 0`      不集成 .NET 3.5
  - `AutoExit = 1`    无人值守结束

## 使用

推送或手动运行 `Build Windows 11 install.esd` 工作流，完成后在运行详情页底部下载 `install-esd-26300.10066` 压缩包，解压即得 `install.esd`。

产物仅包含 `install.esd`，可直接放入 HotPE 启动 U 盘，用 WinNTSetup 等 PE 安装器加载安装。
