# SketchUp 工作流套件 — 项目成果总结

> 更新:2026-09-06 · 仓库:github.com/muliziqi/sketchup-workflow · 全部经本机 SketchUp 2026 + AutoCAD 2027 实战验证

## 一、这套东西是什么

给"AI 驱动 SketchUp 建模"准备的完整工作台,分三层:

1. **知识层**:9 篇工作流文档(模板→建模规范→组件→材质→场景出图→渲染→插件→协作→AI 集成)+ 快捷键方案 + 还原作业指南
2. **自动化层**:两条实战管线 + MCP 桥 + 4 个常驻脚本
3. **案例层**:3 个真实建筑模型(1 个 CAD 转模 + 2 个照片/图纸还原)

## 二、成果清单

### 工作流文档(`01~09 + 快捷键方案`)
模板制作、建模三条铁律与 7 步流程、组件/标记体系、材质命名、场景出图、渲染管线、插件精选、文件协作、AI 集成——含每篇的自查清单。

### CAD 转模管线(`pipeline/`)
```
DWG --(AutoCAD COM: SaveAs DXF)--> DXX --(parse_dxf.ps1 文本解析)--> JSON --(build.rb)--> SketchUp 模型
```
- `export_dxf.ps1`:AutoCAD COM 只做一次 SaveAs(格式码 65),规避逐图元访问的卡死
- `parse_dxf.ps1`:纯文本状态机解析 LINE/LWPOLYLINE/老式 POLYLINE/ARC/CIRCLE/INSERT/MTEXT,块定义递归展平
- `build.rb`:描线→find_faces→细长面推成墙、大面推成楼板、块定义组件化布置
- 实战:Floor Plan Sample.dwg(4500 图元)→ 墙 61/幕墙 168/柱 30/隔断 507/家具组件 273/门 39/标签 55

### 还原作业指南(`pipeline/photo_to_model.md`)
从照片/图纸还原建筑的标准打法:精度分级(L1 体块/L2 深化/L3 施工)、资料转换(PDF→PNG 用 WinRT 系统API)、尺寸标定(比例尺像素比)、建模骨架、视觉闭环、踩坑清单。

### SketchUp MCP 桥 v1.3(`mcp/`)
- `su_mcp_bridge.rb`:SketchUp 内 TCP:5768 JSON 服务(仅本机回环)
- `su_mcp_server.mjs`:零依赖 Node stdio MCP 服务器,9 个工具(ping/model_info/tags/pages/eval_ruby/save/export_png/snapshot/look_around)
- 双通道执行:UI 线程定时器优先 + 失焦 2 秒自动降级工作线程;每次 start 强制重建定时器

### 实战案例(`examples/`)
| 案例 | 方法 | 结果 |
|---|---|---|
| Floor Plan Sample.dwg | CAD 管线 | 办公楼层白模(见上数据) |
| 流水别墅 Fallingwater | 坐标生成 | 四层挑板/溪流瀑布/客舍连廊/配景,700 面 |
| 拉塔皮住宅 Maison Latapie | 图纸实测 + 照片对照 | 12×12.6m 单坡体量 + 全高钢架阳光房,610 面 |

## 三、当前模型状态

- **FloorPlan_Sample_v01.skp**:几何完整;已知限制=单线墙不闭合(墙偏稀疏)、门未开洞
- **Fallingwater_v01.skp**:完成度高;瀑布/水面/挑板/客舍齐
- **Latapie_v02.skp**:按 1:100 图纸实测重建(单坡屋面 4.7→6.5m;住宅两层 5.3m 深 + 7.3m 通高阳光房);经三轮视觉修正——围护改开放钢架形态(大面积半透明板在 write_image 渲染中呈灰实心,属 SketchUp 导出渲染限制)、门窗依实拍重排、树单位 bug 已修

## 四、已知限制与待办

1. FloorPlan:单线墙闭合算法(平行线配对)未做;门洞未开
2. Latapie:内部家具未布置;阳光房围护为开放形态(半透明板渲染灰实心,系 SketchUp 导出限制,数据层材质正确)
3. 图纸解析:扫描版 PDF 需先转 PNG(render_pdf.ps1 已备)
4. 桥的限制:SketchUp 失焦/最小化时视图命令失效(几何命令有工作线程兜底)

## 五、使用入口

- 工作流文档:从 [README.md](README.md) 目录进入
- CAD 转模:[pipeline/README-管线说明.md](pipeline/README-管线说明.md)
- 照片/图纸还原:[pipeline/photo_to_model.md](pipeline/photo_to_model.md)
- MCP 桥:[mcp/README-MCP桥安装.md](mcp/README-MCP桥安装.md)
- 脚本:[scripts/README-脚本使用说明.md](scripts/README-脚本使用说明.md)
