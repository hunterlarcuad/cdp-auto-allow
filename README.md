# Chrome CDP Auto Allow

macOS 后台工具：自动点击 Chrome DevTools Protocol 远程调试确认弹窗的「允许」按钮。

## 适用场景

- Claude Code、OpenClaw、Playwright 等工具通过 CDP 连接 Chrome 时弹出授权框
- Mac mini、远程 Mac、无人值守机器上无法手动点击确认
- Chrome 149+ 必须通过 UI 开启远程调试（命令行参数不再生效）

## 原理

1. AppleScript 编译为 `.app` bundle，注册为 LaunchAgent 常驻运行
2. 通过 macOS Accessibility API 读取 Chrome 的 UI 树
3. 扫描 Google Chrome / Chrome Canary / Chromium 的窗口
4. 匹配远程调试关键词 + 确认词
5. 自动点击 Allow 按钮，或对 AXUnknown 弹窗发送 Return 键

## 安装

```bash
git clone https://github.com/hunterlarcuad/cdp-auto-allow.git
cd cdp-auto-allow
chmod +x scripts/install.sh scripts/uninstall.sh
./scripts/install.sh
```

### 授权 Accessibility

1. **System Settings > Privacy & Security > Accessibility**
2. 点击 `+`，按 `Cmd+Shift+G`，粘贴路径（install.sh 会输出）
3. 打开开关

## 配置

安装后配置文件位于 `~/.config/cdp-auto-allow/config.json`：

```json
{
  "pollInterval": 3,
  "maxLogDays": 7
}
```

| 参数 | 类型 | 默认值 | 说明 |
|------|------|--------|------|
| `pollInterval` | number | 3 | 扫描间隔（秒）。检测到弹窗后约 0.4~`pollInterval` 秒内自动点击。越大越省 CPU，但响应越慢 |
| `maxLogDays` | number | 7 | 日志保留天数。`/tmp/cdp-auto-allow/` 下的日志文件超过此天数自动删除 |

修改配置**不需要重新编译**，下次 idle 循环自动生效。首次安装时从 `config.example.json` 复制，之后修改不会覆盖已有配置。

## 日志

- 路径：`/tmp/cdp-auto-allow/YYYY-MM-DD.log`（按天分割）
- 自动清理超过 `maxLogDays` 天的旧日志
- 查看当天日志：`tail -f /tmp/cdp-auto-allow/$(date +%Y-%m-%d).log`

## 验证

```bash
# 查看 LaunchAgent 状态
launchctl list com.local.cdp-auto-allow

# 手动 dry-run（不真正点击）
osascript scripts/cdp-auto-allow.scpt --dry-run
```

成功自动点击时，日志通常会出现：

```text
Google Chrome PID=... sheets=1
Matched Chrome CDP/DevTools prompt
Clicking allow button: 允许
Approved Chrome CDP/DevTools prompt
```

如果只看到 `windows=...`，但没有 `sheets=1`，表示当前扫描到的 Chrome 窗口里没有远程调试确认 sheet。

## 卸载

```bash
./scripts/uninstall.sh
```

## Chrome 远程调试开启

Chrome 149+ 需要在 UI 中手动开启：

1. Chrome 地址栏打开 `chrome://inspect/#remote-debugging`
2. 勾选 **Allow remote debugging for this browser instance**
3. 用以下命令启动 Chrome：
   ```bash
   /Applications/Google\ Chrome.app/Contents/MacOS/Google\ Chrome \
     --remote-debugging-port=9222 \
     '--profile-directory=Profile 3' \
     'chrome://newtab' &
   ```

## 关键经验

### Chrome 149 忽略命令行参数

Chrome 149+ 在 macOS 上**不再响应** `--remote-debugging-port` 命令行参数。必须在 Chrome UI 中通过 `chrome://inspect/#remote-debugging` 页面手动开启。

### TCC 授权与代码签名

- Accessibility 权限基于代码签名 hash 绑定
- 每次重新编译 `.app` bundle，签名变化，TCC 授权失效
- 因此**配置外置到 `config.json`**，避免频繁重新签名
- 重新授权后，如果日志仍出现 `“CDP Auto Allow”不允许辅助访问`，结束旧 applet 进程，让 launchd 拉起新实例：
  ```bash
  pkill -f "$(pwd)/CDP Auto Allow.app/Contents/MacOS/applet"
  ```

### Chrome 149 中文确认弹窗

Chrome 149 在中文系统中会把远程调试确认框暴露为当前窗口的 `AXSheet`：

```text
AXSheet name=要允许远程调试吗？
AXStaticText: 一款外部应用请求完全控制此 Chrome 会话...
AXButton desc=取消
AXButton desc=允许
```

脚本会优先扫描 `sheet`，匹配中文/英文远程调试文案，并通过按钮的 `name`、`description` 或 `value` 查找 `Allow` / `允许`。

### 为什么不深扫普通浏览器窗口

普通 Chrome / Chromium 页面可能暴露很大的 Accessibility UI 树，例如标签页、扩展、网页内容、通知页等。完整递归扫描这些窗口会导致一轮扫描耗时十几秒甚至更久，远程调试弹窗会因此迟迟得不到处理。

当前策略只扫描：

- Chrome / Chromium 窗口上的 `sheet`
- 小型 `AXUnknown` 对话框
- 未命名且包含 Cancel/Allow 按钮的窗口

这能避免卡在普通网页 UI 树里，同时覆盖 Chrome CDP 远程调试确认框。

### 为什么不用裸 osascript

裸 `osascript` 是 Apple 签名的系统二进制，每次 macOS 更新后 TCC 条目失效。编译为独立 `.app` bundle（`NSUIElement=true` 隐藏 Dock 图标），授权一次后长期有效。

## 安全说明

- Accessibility 权限允许读取并点击本机 UI
- CDP 连接可以控制浏览器页面、读取登录态
- 建议使用专门的自动化 Chrome Profile，而非日常浏览器
- CDP 绑定 `127.0.0.1`，不接受外部连接

## License

MIT
