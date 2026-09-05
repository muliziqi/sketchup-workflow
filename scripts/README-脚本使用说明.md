# 脚本使用说明

4 个脚本安装后会注册到菜单:**扩展程序 > SU工作流**(即 Plugins 菜单下的"SU工作流"子菜单)。

所有脚本的操作都包在撤销块里——**Ctrl+Z 一次即可整体撤销**;清理类脚本运行前请先保存文件。

## 三种用法

### A. 装成常驻插件(推荐)

把 4 个 `.rb` 文件复制到插件目录,重启 SketchUp:

- Windows:`%APPDATA%\SketchUp\SketchUp 20XX\SketchUp\Plugins`(资源管理器地址栏直接粘贴 `%APPDATA%` 回车再找)
- macOS:`~/Library/Application Support/SketchUp/SketchUp 20XX/SketchUp/Plugins`

### B. 临时使用(不改配置)

`窗口 > Ruby控制台` → 用记事本打开 `.rb` 文件全选复制 → 粘贴到控制台回车 → 菜单里点对应命令。

### C. 控制台直接调用

```ruby
SKWF.setup_template            # 初始化标准模板
SKWF.clean_model               # 一键清理
SKWF.model_report              # 体检报告
SKWF.export_scenes             # 批量导出场景,默认 1920×1080
SKWF.export_scenes(3840, 2160) # 指定分辨率导出
```

## 脚本一览

| 脚本 | 菜单名 | 作用 |
|---|---|---|
| skwf_setup_template.rb | 01 初始化标准模板 | 一键建 9 个标准标记 + 7 个标准场景 + 单位(米/十进制) |
| skwf_clean_model.rb | 02 一键清理模型 | 删孤立线、空群组,清未使用的材质/标记/组件定义 |
| skwf_model_report.rb | 03 模型体检报告 | 面数/组件/材质统计 + 最重组件 Top10,结果存 txt |
| skwf_export_scenes.rb | 04 批量导出场景图片 | 每个场景按顺序导出 PNG 到模型旁的 exports/ 文件夹 |

## 备注

- 脚本基于 SketchUp 2020+ 官方 Ruby API 编写;界面上叫"标记",API 里仍是 layers。
- 运行出问题时打开 Ruby 控制台,把红色报错文本复制出来排查。
- 脚本只动当前打开的模型,不会写 SketchUp 配置。
