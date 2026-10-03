# SketchUp MCP 桥安装与使用

让 ZCode / Claude Desktop / Cursor 等 MCP 客户端直接驱动本机 SketchUp(查模型、跑 Ruby、存盘、导图)。

## 架构

```
MCP 客户端(ZCode/Claude/Cursor)
   │  stdio (JSON-RPC)
   ▼
su_mcp_server.mjs        —— 本文件,零依赖 Node 脚本
   │  TCP 127.0.0.1:5768 (每行一个 JSON)
   ▼
su_mcp_bridge.rb         —— SketchUp 插件,在 SketchUp 内执行
```

社区同款架构参考 [mhyrr/sketchup-mcp](https://github.com/mhyrr/sketchup-mcp)(WebSocket 版);本实现为零依赖精简版,协议一致思路。

## 安装

1. 把 `su_mcp_bridge.rb`(v1.3)复制到插件目录并重启 SketchUp:
   - Windows: `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins\`(资源管理器地址栏粘贴 `%APPDATA%` 回车再找)
   - macOS: `~/Library/Application Support/SketchUp/SketchUp 2026/SketchUp/Plugins/`
2. MCP 客户端里添加服务器:

```json
{
  "mcpServers": {
    "sketchup": {
      "command": "node",
      "args": ["C:/path/to/su_mcp_server.mjs"]
    }
  }
}
```

## 社区适配器(可与本桥并列)

仓库附带社区插件主文件 `mcp/community-plugin-main.rb`(来源与许可状态见 [../THIRD-PARTY-NOTICES.md](../THIRD-PARTY-NOTICES.md));它走 **TCP 9876** 的社区协议(JSON-RPC,`{command,parameters,id}`),由 `community-mcp-stdio.mjs` 适配成 stdio MCP。与本桥(5768)端口不同,可同时安装、在 MCP 客户端里并存两条服务器。

安装步骤:

1. 把 `mcp/community-plugin-main.rb` 复制到 SketchUp 插件目录并重启 SketchUp:
   - Windows: `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins\`
   - macOS: `~/Library/Application Support/SketchUp/SketchUp 2026/SketchUp/Plugins/`
2. 启动社区桥的 TCP 服务,两种方式任选:
   - SketchUp 菜单 **扩展程序(Extensions) → SketchupMCP → Start Server**;
   - 或在 Ruby 控制台执行:`SU_MCP.instance_variable_get(:@server)&.start`
3. MCP 客户端里再加一条社区 stdio 服务器:

```json
{
  "mcpServers": {
    "sketchup-community": {
      "command": "node",
      "args": ["C:/path/to/community-mcp-stdio.mjs"]
    }
  }
}
```

注:社区适配器本身不解析任何命令行参数;`--community` 旗标只有测试替身 `tests/fake_bridge.mjs` 需要(用于切换假桥应答协议),生产注册不要携带。

注意:社区插件同样受"失焦/最小化停摆"限制(见下);其 Start Server 状态不会随 SketchUp 重启自动恢复,每次启动 SketchUp 后需重新触发。

## 工具列表

| 工具 | 作用 |
|---|---|
| su_ping | 心跳,返回 SketchUp 版本与当前模型名 |
| su_model_info | 模型概况(实体数/组件数/场景数/包围盒) |
| su_tags / su_pages | 标记列表 / 场景列表 |
| su_eval_ruby | 在 SketchUp 内执行任意 Ruby(`model` 变量可用) |
| su_save | 保存模型 |
| su_export_png | 导出当前视图 PNG |
| su_snapshot | 即时预览:可带 camera(eye/target/up/persp),输出到指定 PNG——AI 改完模型立刻"看" |
| su_look_around | 一次输出 5 张检查快照(四角环绕+顶视)到 exports/preview_*.png |
| su_zoom_extents | 全屏缩放 |

## 已知限制

- **SketchUp 失去前台焦点时,UI 定时器暂停、`active_view` 变 nil**:视图类命令(snapshot/look_around/export)会失败;几何类命令(eval/save)有工作线程兜底仍可执行。桥 v1.3 会在每次 `start`(含菜单"重启服务"与脚本热重载)时强制重建定时器。
- **SketchUp 最小化 = Ruby 运行时整体冻结**,任何命令都不响应。
- 因此 AI 视觉闭环的标准动作:桌面自动化把 SketchUp 调到前台 → 发 snapshot/look_around → 读取 PNG 审查 → 迭代;若返回 nil,重新激活窗口再试一次。
- `su_eval_ruby` 能执行任意 Ruby,只监听 127.0.0.1,但本机任何程序都能连——请勿在公共环境长期开启。
- 大批量几何操作建议打包成一次 eval(如 `load 'xxx.rb'`),减少往返。
