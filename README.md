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

修改配置**不需要重新编译**，下次 idle 循环自动生效。

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

### 为什么不用裸 osascript

裸 `osascript` 是 Apple 签名的系统二进制，每次 macOS 更新后 TCC 条目失效。编译为独立 `.app` bundle（`NSUIElement=true` 隐藏 Dock 图标），授权一次后长期有效。

## 安全说明

- Accessibility 权限允许读取并点击本机 UI
- CDP 连接可以控制浏览器页面、读取登录态
- 建议使用专门的自动化 Chrome Profile，而非日常浏览器
- CDP 绑定 `127.0.0.1`，不接受外部连接

## License

MIT
