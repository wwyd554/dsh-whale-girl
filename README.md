# DeepSeek 大肥鱼

一个常驻 macOS 桌面的 DeepSeek 大肥鱼桌宠，也可作为 DSH 页面挂件使用。

<p align="center">
  <img src="assets/whale-girl.png" width="260" alt="DeepSeek 大肥鱼桌宠">
</p>

## 主要功能

- **macOS 独立桌宠**：透明、无边框、始终置顶，可跨应用显示并拖动位置。
- **点击互动**：单击整只大肥鱼会闭眼，并播放轻微的果冻回弹动画。
- **顺序信息卡**：每次点击依次显示“峰谷时期 → DeepSeek 余额 → 随机吐槽”。
- **自动收起**：信息卡显示 4 秒后自动消失；连续点击会切换内容并重新计时。
- **峰谷颜色**：“低谷时期”为绿色，“高峰时期”为红色。
- **随机吐槽**：内置多条桌宠台词，每轮随机选择并避免连续重复。
- **DeepSeek 连接**：通过官方 API Key 验证账号并读取余额。
- **钥匙串保护**：API Key 只保存在 macOS 钥匙串，不写入项目文件、状态 JSON 或日志。
- **DSH 页面挂件**：保留原项目的页面内挂件、余额、上下文提醒和交互功能。

## 下载与启动

前往 [Releases](https://github.com/wwyd554/dsh-whale-girl/releases/latest) 下载最新版：

- `DSH-Whale-Girl-macOS-*.zip`：macOS 独立桌宠。
- `dsh-whale-girl-*.tgz`：DSH 插件包。

### macOS 独立桌宠

1. 解压下载的 ZIP。
2. 将“DSH 大肥鱼.app”拖入“应用程序”或桌面。
3. 双击启动。

首次打开若被 macOS 拦截，请右键应用，选择“打开”，再确认一次。项目目前使用本地临时签名，系统也可能询问是否允许访问钥匙串；确认应用来源后选择“允许”。

终端启动方式：

```bash
open "/Applications/DSH 大肥鱼.app"
```

需要开机自动运行时，可在“系统设置 → 通用 → 登录项”中添加该应用。

## 连接 DeepSeek

首次启动且尚未保存 Key 时，会自动打开连接窗口。也可以右键桌宠，选择“连接 DeepSeek…”或“DeepSeek 账号设置…”。

1. 在 [DeepSeek 开放平台](https://platform.deepseek.com/api_keys) 创建 API Key。
2. 在桌宠窗口中输入或粘贴 Key。
3. 点击“验证并保存”。
4. 验证成功后窗口会自动关闭，余额会定时刷新。

再次进入账号设置时只显示连接状态、“替换 Key”和“断开连接”。只有点击“替换 Key”后才会重新显示输入框；新 Key 验证成功前，原 Key 不会被覆盖。

桌宠调用的官方接口：

- 认证方式：`Authorization: Bearer <API_KEY>`
- 余额接口：`GET https://api.deepseek.com/user/balance`

## DeepSeek 峰谷规则

按照 [DeepSeek 官方定价说明](https://api-docs.deepseek.com/zh-cn/quick_start/pricing/)：

- 北京时间周一至周五 `09:00–12:00`、`14:00–18:00` 为高峰时段。
- 工作日其他时间为低谷时段。
- 周六、周日全天为低谷时段。
- 低谷价格为高峰价格的一半。

桌宠会按北京时间自动判断，无需手动切换。

## DSH 插件安装

下载 Release 中的 `.tgz` 后执行：

```bash
dsh plugin --profile web add ./dsh-whale-girl-0.7.11.tgz
```

完全退出并重新打开 DSH Desktop 后生效。独立桌宠运行时，页面内的同款挂件会自动隐藏，避免同时出现两只。

## 本地开发

环境要求：Node.js、pnpm、Swift 编译工具链，以及 macOS 13 或更高版本。

```bash
pnpm install
pnpm typecheck
pnpm test
pnpm build
./macos/WhaleGirlDesktop/build.sh
```

构建结果：

- DSH 插件代码：`lib/`
- macOS 应用：`macos/WhaleGirlDesktop/build/DSH 大肥鱼.app`

## 隐私与安全

- API Key 存储在 macOS 钥匙串服务 `local.dsh.whalegirl.desktop` 中。
- 源码、安装包和 Git 历史不包含用户 API Key。
- 项目已忽略 `.env`、本地构建产物、插件安装包和运行状态文件。
- 桌宠不会读屏、监听键盘或上传桌面内容。
- 余额请求仅发送至 DeepSeek 官方 API。

## 项目来源

本项目基于 [nickkkkkk123123/dsh-whale-girl](https://github.com/nickkkkkk123123/dsh-whale-girl) 的 DSH 页面挂件继续开发。当前版本新增并重做了 macOS 独立桌宠、角色素材、点击动画、顺序气泡、随机吐槽、钥匙串连接以及新版峰谷规则等功能。

感谢原项目贡献者。本仓库依照原项目的 MIT License 发布。

## License

[MIT](./LICENSE)
