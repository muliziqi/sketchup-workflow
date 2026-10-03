# encoding: UTF-8
# ============================================================
# SU工作流 · 01 初始化标准模板
# 作用: 为当前空白文件建立 标准标记体系 + 标准场景集 + 单位设置
#
# 用法 A: 新建空白文件 > 窗口 > Ruby控制台 > 粘贴本文件全部内容 > 回车
#         然后菜单: 扩展程序 > SU工作流 > 01 初始化标准模板
# 用法 B: 把本文件复制到 Plugins 文件夹, 重启 SketchUp 后直接用菜单
#
# 运行后: 文件 > 另存为模板, 以后新建项目都用它
# 兼容: SketchUp 2020+(界面上叫"标记", API 里仍是 layers)
# ============================================================
require 'sketchup.rb'

module SKWF
  # 内联守卫: 本文件可能不是最先加载(按字母序 skwf_setup_template 反而最后),
  # 先加载的文件引用 SKWF.workflow_menu 时会崩 —— 每个文件自带同一份 helper
  unless respond_to?(:workflow_menu)
    def self.workflow_menu
      @workflow_menu ||= UI.menu('Plugins').add_submenu('SU工作流')
    end
  end

  STANDARD_TAGS = %w[
    00-底图 01-结构 02-墙体门窗 03-楼板屋面
    04-楼梯 05-家具 06-配景 07-临时 10-参考
  ].freeze

  # 眼点/目标点坐标为 API 内部单位(英寸), 只影响方向, 比例由 zoom_extents 校正
  STANDARD_SCENES = {
    'SC-00-顶视图' => { eye: [0, 0, 100_000],  target: [0, 0, 0],      up: [0, 1, 0], proj: 'ParallelProjection' },
    'SC-01-南立面' => { eye: [0, -100_000, 0], target: [0, 0, 0],      up: [0, 0, 1], proj: 'ParallelProjection' },
    'SC-02-北立面' => { eye: [0, 100_000, 0],  target: [0, 0, 0],      up: [0, 0, 1], proj: 'ParallelProjection' },
    'SC-03-东立面' => { eye: [100_000, 0, 0],  target: [0, 0, 0],      up: [0, 0, 1], proj: 'ParallelProjection' },
    'SC-04-西立面' => { eye: [-100_000, 0, 0], target: [0, 0, 0],      up: [0, 0, 1], proj: 'ParallelProjection' },
    'SC-05-轴测'   => { eye: [80_000, -80_000, 60_000], target: [0, 0, 0],     up: [0, 0, 1], proj: 'ParallelProjection' },
    'SC-06-透视'   => { eye: [12_000, -12_000, 6_000],  target: [0, 0, 1_500], up: [0, 0, 1], proj: 'Perspective' }
  }.freeze

  def self.setup_template
    model = Sketchup.active_model

    # 单位: 米 / 十进制 / 2 位小数(不影响 API 内部以英寸计算)
    begin
      units = model.options['UnitsOptions']
      units['LengthUnit']      = 4 # 0英寸 1英尺 2毫米 3厘米 4米
      units['LengthFormat']    = 0 # 十进制
      units['LengthPrecision'] = 2
    rescue StandardError => e
      puts "单位设置跳过: #{e.message}"
    end

    model.start_operation('初始化标准模板', true)
    begin
      view = model.active_view

      # 1. 标准标记
      STANDARD_TAGS.each { |t| model.layers.add(t) if model.layers[t].nil? }

      # 2. 标准场景
      # SketchUp 2026 兼容: 探测 Pages 可用的建场景方法(add_page 可能被改名,
      # 同 pipeline/build.rb 的探测清单)
      pages = model.pages
      pages_add = [:add_page, :add, :add_scene, :new_page, :push].find { |m| pages.respond_to?(m) }
      raise 'Pages 没有可用的建场景方法' if pages_add.nil?
      exist = pages.to_a.map(&:name)
      created = 0
      set_proj = lambda do |proj|
        # 2026 移除了 View#projection=, 投影改由 Camera 第 4 参数控制; 老版本仍可用
        begin
          view.projection = proj if view.respond_to?(:projection=)
        rescue StandardError
        end
      end
      STANDARD_SCENES.each do |name, cfg|
        next if exist.include?(name)
        persp = (cfg[:proj] == 'Perspective')
        view.camera =
          begin
            Sketchup::Camera.new(cfg[:eye], cfg[:target], cfg[:up], persp)
          rescue StandardError
            Sketchup::Camera.new(cfg[:eye], cfg[:target], cfg[:up])
          end
        set_proj.call(cfg[:proj])
        view.zoom_extents unless persp
        pg = pages.send(pages_add, name)
        created += 1
        # 2026 的 pages.add 不再自动快照当前视图 —— 必须把相机写进页面,
        # 只建页不写相机会产出"空相机"场景
        begin
          pg.camera = view.camera
          pg.use_camera = true
        rescue StandardError
        end
        # 兜底: 选中页面后 update 从当前视图刷新全部场景属性
        if pages.respond_to?(:selected_page=) && pg.respond_to?(:update)
          begin
            pages.selected_page = pg
            flags = 0
            Sketchup::Page.constants.each do |c|
              flags |= Sketchup::Page.const_get(c) if c.to_s.start_with?('PAGE_USE')
            end
            pg.update(flags) if flags > 0
          rescue StandardError => e
            puts "场景 '#{name}' update 跳过: #{e.message}"
          end
        end
      end
      set_proj.call('Perspective')
      view.zoom_extents

      model.commit_operation
      UI.messagebox("完成:#{STANDARD_TAGS.size} 个标准标记 + 新建 #{created} 个场景。\n\n下一步:\n文件 > 另存为模板")
    rescue StandardError => e
      model.abort_operation
      UI.messagebox("初始化失败, 已回滚: #{e.message}")
    end
  end

end

unless file_loaded?(__FILE__)
  SKWF.workflow_menu.add_item('01 初始化标准模板') { SKWF.setup_template }
  file_loaded(__FILE__)
end
