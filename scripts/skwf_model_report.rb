# encoding: UTF-8
# ============================================================
# SU工作流 · 03 模型体检报告
# 作用: 统计面数/组件/材质等健康指标, 找出最"重"的组件定义
# 输出: Ruby 控制台; 模型已保存时, 同时写入模型旁的 模型体检报告.txt
# 说明: 面数按实例展开统计, 即渲染时实际绘制的规模
# ============================================================
require 'sketchup.rb'

module SKWF
  FACE_BUDGET = 500_000 # 超过该面数提示优化

  def self.model_report
    model = Sketchup.active_model
    stats = Hash.new(0)

    walk = lambda do |entities|
      entities.each do |e|
        case e
        when Sketchup::Face
          stats[:faces] += 1
        when Sketchup::Edge
          stats[:edges] += 1 unless e.deleted?
        when Sketchup::Group
          stats[:groups] += 1
          walk.call(e.entities)
        when Sketchup::ComponentInstance
          stats[:instances] += 1
          walk.call(e.definition.entities)
        end
      end
    end
    walk.call(model.entities)

    used_defs = model.definitions.select { |d| !d.image? && d.instances.any? }
    unused_defs = model.definitions.count - used_defs.size
    heavy = used_defs.map { |d| [d.name, d.entities.grep(Sketchup::Face).size] }
                     .sort_by { |_, n| -n }
                     .first(10)

    size_mb = model.path.empty? ? nil : (File.size(model.path) / 1024.0 / 1024.0).round(1)

    lines = []
    lines << '===== 模型体检报告 ====='
    lines << "文件: #{model.path.empty? ? '(未保存)' : model.path}"
    lines << "文件大小: #{size_mb ? "#{size_mb} MB" : '未保存, 无法统计'}"
    lines << ''
    lines << "渲染面数(实例展开): #{stats[:faces]}"
    lines << "渲染线数(实例展开): #{stats[:edges]}"
    lines << "群组: #{stats[:groups]} / 组件实例: #{stats[:instances]}"
    lines << "组件定义: #{used_defs.size} 个在用 / #{unused_defs} 个未使用"
    lines << "材质: #{model.materials.count} / 标记: #{model.layers.count} / 场景: #{model.pages.count}"
    lines << ''
    lines << '最重的组件定义 Top10 (面数):'
    heavy.each_with_index do |(name, n), i|
      lines << format('  %2d. %-40s %d', i + 1, name, n)
    end
    lines << ''
    lines << '诊断:'
    lines << "  - #{stats[:faces] > FACE_BUDGET ? "总面数 #{stats[:faces]} 超过预算 #{FACE_BUDGET}, 建议减面/精简配景" : "总面数 #{stats[:faces]}, 在预算内"}"
    lines << "  - #{unused_defs.positive? ? "有 #{unused_defs} 个未使用组件定义, 跑 02 一键清理" : '无未使用组件定义'}"

    text = lines.join("\n")
    puts text

    if !model.path.empty?
      report_path = File.join(File.dirname(model.path), '模型体检报告.txt')
      File.open(report_path, 'w:UTF-8') { |f| f.write("\uFEFF" + text) }
      puts "报告已保存: #{report_path}"
    end
    UI.messagebox(lines[0, 15].join("\n") + "\n\n完整报告见 Ruby 控制台#{model.path.empty? ? '' : '与模型旁 txt 文件'}")
  rescue StandardError => e
    UI.messagebox("体检失败: #{e.message}")
  end
end

unless file_loaded?(__FILE__)
  SKWF.workflow_menu.add_item('03 模型体检报告') { SKWF.model_report }
  file_loaded(__FILE__)
end
