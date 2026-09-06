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

1. 把 `su_mcp_bridge.rb` 复制到插件目录并重启 SketchUp:
   - Windows: `%APPDATA%\SketchUp\SketchUp 2026\SketchUp\Plugins\`
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

## 工具列表

| 工具 | 作用 |
|---|---|
| su_ping | 心跳,返回 SketchUp 版本与当前模型名 |
| su_model_info | 模型概况(实体数/组件数/场景数/包围盒) |
| su_tags / su_pages | 标记列表 / 场景列表 |
| su_eval_ruby | 在 SketchUp 内执行任意 Ruby(`model` 变量可用) |
| su_save | 保存模型 |
| su_export_png | 导出当前视图 PNG |
| su_zoom_extents | 全屏缩放 |

## 已知限制

- **SketchUp 最小化时整个 Ruby 运行时冻结**(主线程不调度),桥无法响应——把它保持打开(可以在后台,但别最小化)。桥 v1.1 已做双通道兜底:窗口失去焦点时 2 秒后自动降级到工作线程执行。
- `su_eval_ruby` 能执行任意 Ruby,只监听 127.0.0.1,但本机任何程序都能连——请勿在公共环境长期开启。
- 大批量几何操作建议打包成一次 eval(如 `load 'xxx.rb'`),减少往返。
