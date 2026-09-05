# encoding: UTF-8
# ============================================================
# SU工作流 · 02 一键清理模型
# 作用: 删除孤立线段与空群组, 清理未使用的 材质/标记/组件定义
# 建议: 出图前、交付前各跑一次; 运行前先保存文件
# 支持 Ctrl+Z 一次整体撤销
# ============================================================
require 'sketchup.rb'

module SKWF
  def self.clean_model
    model = Sketchup.active_model
    model.start_operation('一键清理模型', true)
    begin
      stray_edges, empty_groups = clean_entities(model.entities)

      mats_before = model.materials.count
      tags_before = model.layers.count
      defs_before = model.definitions.count

      model.materials.purge_unused
      model.layers.purge_unused
      model.definitions.purge_unused

      msg = [
        '清理完成:',
        "- 孤立线段: #{stray_edges} 条",
        "- 空群组:   #{empty_groups} 个",
        "- 材质:     #{mats_before} → #{model.materials.count}",
        "- 标记:     #{tags_before} → #{model.layers.count}",
        "- 组件定义: #{defs_before} → #{model.definitions.count}",
        '',
        '记得 文件 > 保存(或另存新版本)。'
      ].join("\n")

      model.commit_operation
      UI.messagebox(msg)
    rescue StandardError => e
      model.abort_operation
      UI.messagebox("清理失败, 已回滚: #{e.message}")
    end
  end

  # 递归清理群组内的孤立线与空组(不进入组件定义, 避免误改共享库件)
  def self.clean_entities(entities)
    stray = 0
    empty_groups = 0

    entities.grep(Sketchup::Edge).each do |edge|
      next if edge.deleted?
      next unless edge.faces.empty?
      edge.erase!
      stray += 1
    end

    entities.grep(Sketchup::Group).each do |group|
      next if group.deleted?
      if group.entities.empty?
        group.erase!
        empty_groups += 1
      else
        a, b = clean_entities(group.entities)
        stray += a
        empty_groups += b
      end
    end

    [stray, empty_groups]
  end
end

unless file_loaded?(__FILE__)
  SKWF.workflow_menu.add_item('02 一键清理模型') { SKWF.clean_model }
  file_loaded(__FILE__)
end
