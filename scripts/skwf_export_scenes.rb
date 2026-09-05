# encoding: UTF-8
# ============================================================
# SU工作流 · 04 批量导出场景图片
# 作用: 把当前模型的每个场景按顺序导出为 PNG
# 输出: 模型文件同目录下的 exports 文件夹, 文件名 = 序号_场景名.png
# 用法: 先保存模型 > 菜单运行 > 完成后到 exports 文件夹取图
# ============================================================
require 'sketchup.rb'

module SKWF
  DEFAULT_WIDTH  = 1920
  DEFAULT_HEIGHT = 1080

  def self.export_scenes(width = DEFAULT_WIDTH, height = DEFAULT_HEIGHT)
    model = Sketchup.active_model
    if model.path.to_s.empty?
      UI.messagebox('请先保存模型文件, 再批量导出。')
      return
    end
    if model.pages.empty?
      UI.messagebox('当前模型没有场景。请先按"05-场景风格与出图"建立场景。')
      return
    end

    dir = File.join(File.dirname(model.path), 'exports')
    Dir.mkdir(dir) unless File.directory?(dir)

    view = model.active_view
    count = 0
    model.pages.each_with_index do |page, i|
      activate_page(model, page)
      safe_name = page.name.gsub(/[\\\/:*?"<>|]/, '_')
      path = File.join(dir, format('%02d_%s.png', i + 1, safe_name))
      begin
        ok = view.write_image(filename: path, width: width, height: height, antialias: true)
      rescue StandardError
        ok = view.write_image(path, width, height, true)
      end
      count += 1 if ok
      puts ok ? "已导出: #{path}" : "导出失败: #{path}"
    end
    UI.messagebox("已导出 #{count}/#{model.pages.count} 张到:\n#{dir}")
  rescue StandardError => e
    UI.messagebox("批量导出失败: #{e.message}")
  end

  # 激活场景: 优先用 selected_page=(切换标记/样式/阴影等全部属性),
  # 老版本无该 API 时退化为仅切换相机
  def self.activate_page(model, page)
    if model.pages.respond_to?(:selected_page=)
      model.pages.selected_page = page
    else
      model.active_view.camera = page.camera
    end
  end
end

unless file_loaded?(__FILE__)
  SKWF.workflow_menu.add_item('04 批量导出场景图片') { SKWF.export_scenes }
  file_loaded(__FILE__)
end
