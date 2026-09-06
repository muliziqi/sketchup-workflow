# CAD → SketchUp 自动建模管线

把 AutoCAD 平面图(DWG/DXF)自动转成 SketchUp 白模的完整管线。已在 SketchUp 2026 + AutoCAD 2027 实战验证(示例:AutoCAD 自带 `Floor Plan Sample.dwg`,4500+ 图元 → 墙体/幕墙/柱/隔断/家具组件/门扇/房间标签全自动建出)。

## 流程

```
DWG ──(AutoCAD COM: SaveAs DXF)──► DXF ──(parse_dxf.ps1 文本解析)──► JSON
                                                                       │
SketchUp ◄──(build.rb: 描线→找面→推拉→组件化)── JSON ◄─────────────────┘
```

| 步骤 | 脚本 | 说明 |
|---|---|---|
| 1. DWG→DXF | `export_dxf.ps1` | 仅用 COM 打开图纸 + SaveAs(格式代码 65=2018 DXF),不做逐图元 COM 访问(那会慢到卡死) |
| 2. DXF→JSON | `parse_dxf.ps1` | 纯文本状态机解析:LINE/LWPOLYLINE/老式 POLYLINE/ARC/CIRCLE/INSERT/MTEXT,块定义递归展平 |
| 3. JSON→模型 | `build.rb` | 在 SketchUp 里:描线 → find_faces → 细长面推成墙、大面推成楼板、块定义做成组件再按插入点+旋转布置 |
| 辅助 | `bridge_call.ps1` | 向 MCP 桥发任意 JSON 命令的测试客户端 |

## 使用

```powershell
# 1. 导出 DXF(改脚本头部的 $dwg 路径)
powershell -File export_dxf.ps1
# 2. 解析(改脚本头部的图层分类表,见下)
powershell -File parse_dxf.ps1
# 3. 建模: SketchUp 打开任意模型后,任选其一
#    a) 有 MCP 桥: 发 eval 命令 load build.rb(见 build_req.json)
#    b) 无桥: 把 z_auto_build 加载器放进 Plugins 重启 SketchUp(见 ../mcp)
#       或窗口 > Ruby控制台: load 'C:/.../build.rb'
```

## 换一张图要改什么

- **parse_dxf.ps1** 顶部的图层分类表:`$wallLayers`(墙)、`$glazLayers`(幕墙)、`$doorLayer`/`$doorNames`(门)、`PANELS_201`(隔断)等,改成目标图的图层名。
- **build.rb** 顶部的高度表:`WALL_H / PANEL_H / FURN_H`(家具块名→推拉高度)、`SKIP_DEFS`(注释类块)。
- 图层名/块名不知道?先跑一遍 parse,统计输出会列出所有图元分布。

## 实战踩坑记录(2026 版 SketchUp)

1. `Pages#add_page` 被改名为 `Pages#add`,且**不再自动快照当前视图**,场景要自己写相机属性。
2. `Page#camera=`、`View#projection=` 被移除;透视/平行改用 `Camera.new(eye,target,up,persp)` 第 4 参数。
3. `DefinitionList#[](字符串)` 按名字查组件定义不可靠 → 自己维护 `名字→定义` 映射。
4. 删除组件定义用 `definitions.remove(def)`,不是 `def.remove`。
5. SketchUp 最小化时主线程停摆,Ruby 后台线程全部冻结(TCP 桥也不响应)——驱动 SketchUp 时别最小化它。
6. AutoCAD COM 逐图元访问属性极慢(4500 图元可卡 20 分钟),务必走 DXF 文本解析。
7. Windows 命令行传中文 JSON 会被编码搞坏,请求体走 UTF-8 文件(`--data-binary @file`)。
