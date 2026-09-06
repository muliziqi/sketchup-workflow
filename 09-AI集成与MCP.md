# 09 · AI 集成与 MCP(让 AI 直接驱动 SketchUp)

> 2026 年的 SketchUp + AI 生态现状调研结论,以及本套件自建的两件武器:CAD→SketchUp 自动建模管线、SketchUp MCP 桥。

## 社区生态调研结论

| 方案 | 形态 | 能力 | 局限 |
|---|---|---|---|
| [Trimble 官方 SketchUp Connector for Claude](https://help.sketchup.com/en/sketchup-claude-connector)(2026.4 发布) | Claude.ai 云端连接器 | 文字/图片→生成 .skp,工具:get_docs / evaluate_py / save_model | **只能新建**,不能编辑现有 .skp;仅支持 Claude;免费 30 个模型后需订阅;模型存 Trimble 侧 |
| [mhyrr/sketchup-mcp](https://github.com/mhyrr/sketchup-mcp) | 本地:SketchUp 插件 ↔ WebSocket:5678 ↔ Node MCP | get_scene_info / execute_ruby_code 等,可编辑现有模型 | 需装 Node 桥;SketchUp 最小化时停摆 |
| [darwin/supex](https://github.com/darwin/supex) | 实验性智能体平台 | AI 直接写/执行 SketchUp Ruby | 偏实验性 |
| [tarkiin/sketchup-mcp](https://mcpservers.org/servers/tarkiin/sketchup-mcp) | 本地 MCP | 程序化建模 | 同类 |

**选型建议**:想"一句话生成一个新模型"用官方 Connector;想"让 AI 操作你机器上正在编辑的模型"(结合本项目管线做 CAD 转换、批量清理、自动出图)用本地桥——这正是我们自建的原因。

## 本套件的两件武器

### 1. CAD → SketchUp 自动建模管线(`pipeline/`)

DWG → DXF → JSON → Ruby 白模,详见 [pipeline/README-管线说明.md](pipeline/README-管线说明.md)。实战记录:4500 图元的办公楼层平面 → 墙 61 面、幕墙 168、柱 30、隔断 507、家具组件 273 件、门 39 樘、房间标签 55 个,全程无手工。

### 2. SketchUp MCP 桥(`mcp/`)

本地 TCP + stdio 双层桥,让任意 MCP 客户端能查模型、跑 Ruby、存盘、导图、**出预览图**。安装见 [mcp/README-MCP桥安装.md](mcp/README-MCP桥安装.md)。

**安全须知**:`su_eval_ruby` 等于把模型控制权交给 AI。只监听 127.0.0.1,但本机程序均可连;执行破坏性操作前让 AI 先 `su_save`。

### AI 视觉闭环("用眼睛看")

AI 建模最大的风险是"盲改"。桥 v1.3 起内置视觉检查命令,与桌面自动化(把 SketchUp 调到前台)配合,形成闭环:

```
改模型(eval/load) → su_snapshot 或 su_look_around(出快照)
   → AI 读取 PNG 用视觉审查(构图/穿模/漏项/比例)
   → 发现问题 → 改脚本 → 再看 → 直到满意 → su_save
```

实战踩坑结论(2026 实机):
1. **SketchUp 失去前台焦点 = UI 定时器暂停 + `active_view` 变 nil**。几何命令有工作线程兜底仍可跑;视图命令(快照/导图)会失败——先激活 SketchUp 窗口再发命令,失败就重试。
2. **最小化 = Ruby 整体冻结**,一切命令无响应。
3. 替代方案:直接对 SketchUp 视口截屏(桌面自动化)同样能让 AI"看",不依赖视图 API;桥的快照命令则能固定相机、批量出检查视角。

### 与其它 AI 审图分工

若同机还有针对 CAD 图纸的 AI 审图管线(查标注、图层、坐标换算),注意分工:图纸层审查交给那条管线;模型层审查(几何、材质、视角、穿模)用本套件的 snapshot/look_around。两者共用"AI 看 → 报告 → 修"的循环模式。

## 与本工作流的结合点

- **02/03 篇的建模规范** → 写进 build.rb(先成组再推拉、组件复用、Tag 体系、材质命名 MAT_部位_名称)
- **05 篇的场景规范** → 脚本自动建 SC-编号场景并批量出图
- **08 篇的文件管理** → 管线产物按 `02-SU源文件/项目名_v01.skp` 归档

## SketchUp 2026 Ruby API 变化备忘(实战踩坑)

写自动化脚本前必读,官方文档滞后于实机:

1. `Pages#add_page` → 改名 `Pages#add`,且不再自动快照当前视图。
2. `Page#camera=`、`View#projection=` 移除;平行/透视改由 `Camera.new(eye, target, up, persp)` 第 4 参数控制。
3. `DefinitionList#[](字符串名)` 不可靠——自己维护 `名字→定义` 的映射表。
4. 删组件定义是 `definitions.remove(def)`,不是 `def.remove`。
5. SketchUp 最小化 = Ruby 运行时整体冻结,后台线程全部停摆(桥的定时器也不跑)。

## 人工兜底

AI 驱动出问题时,人工永远可用:`窗口 > Ruby控制台`,粘贴 `load 'xxx.rb'`。所有自动化脚本都应保持"能被人手执行"这一底线。
