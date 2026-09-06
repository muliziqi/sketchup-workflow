# encoding: UTF-8
# ============================================================
# CAD 平面图 -> SketchUp 白模  (Floor Plan Sample.dwg)
# 用法: 在 SketchUp 的 Ruby 控制台执行:
#   load 'C:/Users/muliz/.zcode/workspace/default/cad2skp/build.rb'
# 可重复运行: 每次先清空当前模型再重建
# 单位: 英寸(与 DWG 一致), 面数预算 < 15 万
# ============================================================
require 'json'

DATA_DIR   = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/data'
OUT_SKP    = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/FloorPlan_Sample_v01.skp'
EXPORT_DIR = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/exports'

WALL_H  = 108.0   # 9' 墙高
SHELF_H = 72.0    # 储物柜高
PANEL_H = 60.0    # 工位隔断高
COL_H   = 120.0   # 柱高
DOOR_H  = 84.0    # 门高
FLOOR_T = 4.0     # 楼板厚

# 家具块 -> 推拉高度(英寸); 不在表内的块只画平面线
FURN_H = {
  'DESK2' => 29, 'DESK3' => 29,
  'FC42X18D' => 52, 'FC15X27A' => 52, 'FILE_CABINETS' => 52,
  'SOFA2' => 30, 'CHAIR7' => 17, 'PRINTER_ISLAND' => 36
}
# 台面物品: 不推拉, 但垫高到桌面上
FURN_Z = { 'COMPUTER' => 30, 'FNPHONE' => 30, 'KEYBOARD' => 30, 'IBMAT' => 30 }
# 跳过的注释类块
SKIP_DEFS = ['NCL-HL', 'RMNUM', 'DOOR', 'DR-36', 'DR-72P', 'DR-69P']
DOOR_W = { 'DR-36' => 36.0, 'DR-72P' => 72.0, 'DR-69P' => 69.0, 'DOOR' => 30.0 }

def jload(name)
  txt = File.read(File.join(DATA_DIR, name)).sub(/\A\xEF\xBB\xBF/, '')
  JSON.parse(txt)
end

model = Sketchup.active_model
begin
  model.entities.clear!
rescue => e
  puts "clear failed: #{e.message}"
end
# 清掉上次运行残留的未使用组件定义(含异常命名的 #1 / Sree / Group#N 等)
# 注意: 2026 里 remove 方法在 DefinitionList 上, 不在 ComponentDefinition 上
begin
  model.definitions.to_a.each do |d|
    model.definitions.remove(d) if d.instances.empty? && !d.image?
  end
rescue => e
  puts "def purge skip: #{e.message}"
end
# 2026 的 DefinitionList#[](字符串) 不可靠, 自己维护名字映射
DEFS_BY_NAME = {}

# ---------- 单位 / 标记 / 材质 ----------
begin
  u = model.options['UnitsOptions']
  u['LengthUnit'] = 0; u['LengthFormat'] = 1; u['LengthPrecision'] = 0
rescue => e
  puts "units skip: #{e.message}"
end

%w[01-结构 02-墙体门窗 03-楼板屋面 05-家具 10-参考].each do |t|
  model.layers.add(t) if model.layers[t].nil?
end

def get_mat(model, name, rgb, alpha = nil)
  m = model.materials[name]
  unless m
    m = model.materials.add(name)
    m.color = Sketchup::Color.new(*rgb)
    m.alpha = alpha if alpha
  end
  m
end

MAT_WALL  = get_mat(model, 'MAT_墙体_白', [242, 240, 235])
MAT_FLOOR = get_mat(model, 'MAT_地面_浅灰', [198, 195, 190])
MAT_CONC  = get_mat(model, 'MAT_柱_混凝土', [152, 150, 148])
MAT_GLASS = get_mat(model, 'MAT_玻璃_清玻', [168, 200, 214], 0.4)
MAT_FURN  = get_mat(model, 'MAT_家具_木', [163, 122, 88])
MAT_PANEL = get_mat(model, 'MAT_隔断_灰蓝', [124, 134, 152])
MAT_DOOR  = get_mat(model, 'MAT_门_木色', [150, 105, 70])

Z = Geom::Vector3d.new(0, 0, 1)

# ---------- 工具 ----------
def add_edges(ents, segs)
  segs.each do |s|
    ents.add_line([s['x1'], s['y1'], 0], [s['x2'], s['y2'], 0])
  end
end

def add_poly(ents, p)
  pts = p['pts'].to_a
  return if pts.size < 2
  n = pts.size
  (n - 1).times { |i| ents.add_line([pts[i][0], pts[i][1], 0], [pts[i+1][0], pts[i+1][1], 0]) }
  if p['closed'] && (pts[n-1][0] != pts[0][0] || pts[n-1][1] != pts[0][1])
    ents.add_line([pts[n-1][0], pts[n-1][1], 0], [pts[0][0], pts[0][1], 0])
  end
end

def find_faces(ents)
  ents.grep(Sketchup::Edge).each { |e| e.find_faces rescue nil }
end

def cleanup_stray(ents)
  # 没找到任何面时保留线框(家具平面仍有用), 只有已形成面时才清孤立线
  return if ents.grep(Sketchup::Face).empty?
  ents.grep(Sketchup::Edge).each do |e|
    next if e.deleted?
    e.erase! if e.faces.empty?
  end
end

# 2026 兼容: Camera 可能支持第 4 个透视参数, 不支持则退回 projection=
def make_cam(eye, target, up, persp)
  begin
    cam = Sketchup::Camera.new(eye, target, up, persp)
    puts "      cam4arg ok, perspective=#{cam.perspective? rescue '?'} (期望 #{persp})"
    return cam
  rescue => e
    puts "      cam4arg 失败(#{e.message}), 退回 3 参数"
  end
  cam = Sketchup::Camera.new(eye, target, up)
  begin
    Sketchup.active_model.active_view.projection = persp ? 'Perspective' : 'ParallelProjection'
  rescue => e
    puts "      projection= 不可用: #{e.message}"
  end
  cam
end

# 通用的 "描线 -> 找面 -> 细长面推墙" 流程
# 返回 [推了的面数, 楼板面数]
def build_walls(ents, segs, height, wall_mat, floor_mat, thin_max, floor_min_area)
  add_edges(ents, segs)
  find_faces(ents)
  pushed = 0
  floors = 0
  ents.grep(Sketchup::Face).each do |f|
    next if f.deleted?
    b = f.bounds
    thin = [b.width, b.depth].min
    area = f.area
    f.reverse! if f.normal.z < 0
    if thin <= thin_max && area < 40000
      f.pushpull(height)
      pushed += 1
    elsif area >= floor_min_area
      f.pushpull(-FLOOR_T)
      floors += 1
    end
  end
  # 按朝向/位置统一上色
  ents.grep(Sketchup::Face).each do |f|
    next if f.deleted?
    b = f.bounds
    if b.max.z <= 0.05 && b.min.z >= -FLOOR_T - 0.05 && area_chk(f, floor_min_area)
      f.material = floor_mat; f.back_material = floor_mat
    else
      f.material = wall_mat; f.back_material = wall_mat
    end
  end
  cleanup_stray(ents)
  [pushed, floors]
end

def area_chk(f, min_area)
  f.area >= min_area
end

# ---------- 1. 墙体 + 楼板 ----------
puts '[1/8] 墙体...'
walls = jload('walls.json')['segs']
g_walls = model.entities.add_group
g_walls.name = 'WALLS'
g_walls.layer = model.layers['02-墙体门窗']
pw, fw = build_walls(g_walls.entities, walls, WALL_H, MAT_WALL, MAT_FLOOR, 12.0, 5000)
puts "    面推拉 #{pw}, 楼板 #{fw}"

# ---------- 2. 储物柜 ----------
puts '[2/8] 储物柜...'
shelv = jload('shelving.json')['segs']
g_shelf = model.entities.add_group
g_shelf.name = 'SHELVING'
g_shelf.layer = model.layers['05-家具']
ps, _ = build_walls(g_shelf.entities, shelv, SHELF_H, MAT_FURN, MAT_FLOOR, 12.0, 100000)
puts "    推拉 #{ps}"

# ---------- 3. 玻璃幕墙 ----------
puts '[3/8] 幕墙...'
glaz = jload('glazing.json')['segs']
g_glass = model.entities.add_group
g_glass.name = 'GLAZING'
g_glass.layer = model.layers['02-墙体门窗']
pg, _ = build_walls(g_glass.entities, glaz, WALL_H, MAT_GLASS, MAT_FLOOR, 14.0, 20000)
g_glass.entities.grep(Sketchup::Face).each do |f|
  next if f.deleted?
  b = f.bounds
  if b.max.z <= 0.05 && b.min.z >= -FLOOR_T - 0.05 && f.area >= 20000
    f.material = MAT_FLOOR; f.back_material = MAT_FLOOR
  else
    f.material = MAT_GLASS; f.back_material = MAT_GLASS
  end
end
puts "    推拉 #{pg}"

# ---------- 4. 柱 ----------
puts '[4/8] 柱...'
cols = jload('columns.json')['segs']
g_col = model.entities.add_group
g_col.name = 'COLUMNS'
g_col.layer = model.layers['01-结构']
pc, _ = build_walls(g_col.entities, cols, COL_H, MAT_CONC, MAT_FLOOR, 60.0, 100000)
puts "    推拉 #{pc}"

# ---------- 5. 工位隔断 ----------
puts '[5/8] 工位隔断...'
panels = jload('panels.json')['polys']
g_panel = model.entities.add_group
g_panel.name = 'PANELS'
g_panel.layer = model.layers['05-家具']
pent = g_panel.entities
panels.each { |p| add_poly(pent, p) }
find_faces(pent)
pp = 0
pent.grep(Sketchup::Face).each do |f|
  next if f.deleted?
  b = f.bounds
  next unless [b.width, b.depth].min <= 8.0 && f.area < 40000
  f.reverse! if f.normal.z < 0
  f.pushpull(PANEL_H)
  pp += 1
end
pent.grep(Sketchup::Face).each do |f|
  next if f.deleted?
  f.material = MAT_PANEL; f.back_material = MAT_PANEL
end
cleanup_stray(pent)
puts "    推拉 #{pp}"

# ---------- 6. 家具组件 ----------
puts '[6/8] 家具...'
defs = jload('block_definitions.json')
defs.each do |name, d|
  next if SKIP_DEFS.include?(name)
  begin
    comp = model.definitions.to_a.find { |d| d.name == name }
    unless comp
      comp = model.definitions.add(name)
      comp.name = name rescue nil
    end
    cent = comp.entities
    cent.clear! rescue nil
    add_edges(cent, d['segs'] || [])
    (d['polys'] || []).each { |p| add_poly(cent, p) }
    find_faces(cent)
    h = FURN_H[name] || 0
    if h > 0
      cent.grep(Sketchup::Face).each do |f|
        next if f.deleted?
        b = f.bounds
        next unless [b.width, b.depth].min <= 60.0
        f.reverse! if f.normal.z < 0
        f.pushpull(h)
      end
      cent.grep(Sketchup::Face).each do |f|
        next if f.deleted?
        f.material = MAT_FURN; f.back_material = MAT_FURN
      end
    end
    cleanup_stray(cent) if h > 0
    cbb = comp.bounds
    if cbb.min.x < -500 || cbb.min.y < -500 || cbb.width > 600 || cbb.depth > 600 || (cbb.width <= 0.01 && cent.length == 0)
      BAD_DEFS << name
      puts "    def #{name}: ents=#{cent.length} 异常尺寸/坐标 (#{cbb.min.x.round} ,#{cbb.min.y.round}) #{cbb.width.round}x#{cbb.depth.round} -> 不实例化"
    else
      DEFS_BY_NAME[name] = comp
      puts "    def #{name}: segs=#{(d['segs']||[]).size} polys=#{(d['polys']||[]).size} ents=#{cent.length} ok"
    end
  rescue => e
    puts "    def #{name} FAILED: #{e.message}"
    BAD_DEFS << name
  end
end
puts "    defs now: #{model.definitions.to_a.map(&:name).reject { |n| n.to_s.start_with?('*') }.sort.join(', ')}"

insts = jload('furniture_instances.json')['insts']
g_furn = model.entities.add_group
g_furn.name = 'FURNITURE'
g_furn.layer = model.layers['05-家具']
cnt = 0
skip_stat = Hash.new(0)
BAD_DEFS = [] unless defined?(BAD_DEFS)
insts.each do |i|
  if BAD_DEFS.include?(i['name'])
    skip_stat[i['name']] += 1
    next
  end
  comp = DEFS_BY_NAME[i['name']]
  if comp.nil?
    skip_stat[i['name']] += 1
    next
  end
  x = i['x'].to_f; y = i['y'].to_f; rot = i['rot'].to_f
  sx = i['sx'].to_f; sy = i['sy'].to_f
  sx = 1.0 if sx == 0; sy = 1.0 if sy == 0
  z = FURN_Z[i['name']] || 0
  tr = Geom::Transformation.translation([x, y, z]) *
       Geom::Transformation.rotation(ORIGIN, Z, rot) *
       Geom::Transformation.scaling(sx, sy, 1.0)
  g_furn.entities.add_instance(comp, tr)
  cnt += 1
end
puts "    跳过的实例: #{skip_stat.map { |k, v| "#{k}x#{v}" }.join(', ')}" unless skip_stat.empty?
puts "    组件实例 #{cnt}"

# ---------- 7. 门 ----------
puts '[7/8] 门...'
doors = jload('doors.json')['insts']
# 过滤: IDOORE 图层是门编号标注, 且剔除平面范围外的野点
doors = doors.reject { |d| d['layer'] == 'IDOORE' || d['x'].to_f < 500 || d['x'].to_f > 3800 || d['y'].to_f < 500 || d['y'].to_f > 3800 }
g_door = model.entities.add_group
g_door.name = 'DOORS'
g_door.layer = model.layers['02-墙体门窗']
dent = g_door.entities
doors.each do |d|
  x = d['x'].to_f; y = d['y'].to_f; rot = d['rot'].to_f
  w = DOOR_W[d['name']] || 36.0
  ct = Math.cos(rot); st = Math.sin(rot)
  dir = Geom::Vector3d.new(ct, st, 0)
  nrm = Geom::Vector3d.new(-st, ct, 0)
  a = [x, y, 0]
  b = [x + w*ct, y + w*st, 0]
  c = [b[0] + 2*nrm.x, b[1] + 2*nrm.y, 0]
  dd = [x + 2*nrm.x, y + 2*nrm.y, 0]
  f = dent.add_face(a, b, c, dd)
  next unless f && !f.deleted?
  f.material = MAT_DOOR; f.back_material = MAT_DOOR
  f.reverse! if f.normal.z < 0
  begin
    f.pushpull(DOOR_H)
  rescue => e
    puts "    door leaf skip: #{e.message}"
  end
  dent.add_arc([x, y, 0], dir, Z, w, 0, Math::PI/2, 12) rescue nil
end
puts "    门扇 #{doors.size}"

# ---------- 8. 参考线 + 房间标签 ----------
puts '[8/8] 标签...'
stairs = jload('stairs.json')['segs']
g_ref = model.entities.add_group
g_ref.name = 'REF'
g_ref.layer = model.layers['10-参考']
add_edges(g_ref.entities, stairs)
grids = jload('grid.json')['segs']
add_edges(g_ref.entities, grids)

labels = jload('labels.json')['labels']
lcnt = 0
labels.each do |l|
  next if l['text'].nil? || l['text'].empty?
  begin
    g = model.entities.add_group
    g.layer = model.layers['10-参考']
    begin
      g.entities.add_3d_text(l['text'], 1, 'Arial', false, false, 10.0, 0.5, true, 0)
    rescue
      g.entities.clear! rescue nil
      g.entities.add_3d_text(l['text'], 1, 'Arial')
    end
    g.transform!(Geom::Transformation.translation([l['x'], l['y'], 1]))
    lcnt += 1
  rescue => e
    puts "    label skip: #{e.message}"
    next
  end
end
puts "    标签 #{lcnt}"

# ---------- 场景 + 出图 + 保存 ----------
bb = model.bounds
c = bb.center
diag = bb.diagonal
puts "模型范围: #{bb.min} -> #{bb.max}"

pages = model.pages
if pages.count > 0
  begin
    pages.to_a.each { |p| pages.erase(p) }
  rescue => e
    puts "pages erase skip: #{e.message}"
  end
end

begin
  view = model.active_view
  # SketchUp 2026 兼容: 探测 Pages 可用的建场景方法(add_page 可能被改名)
  PAGES_ADD = [:add_page, :add, :add_scene, :new_page, :push].find { |m| pages.respond_to?(m) }
  puts "Pages 实例方法: #{Sketchup::Pages.instance_methods(false).sort.join(' ')}" rescue nil
  puts "Pages 新建场景方法: #{PAGES_ADD.inspect}"
  if PAGES_ADD.nil?
    raise 'Pages 没有可用的建场景方法'
  end
  # 2026 的 pages.add 不再自动快照当前视图, 建完必须把相机写进页面
  def add_scene(pages, method, name, cam)
    view = Sketchup.active_model.active_view
    view.camera = cam
    view.zoom_extents
    pg = pages.send(method, name)
    begin
      pg.camera = view.camera
      pg.use_camera = true
    rescue
    end
    # 2026 兜底: 选中页面后 update 从当前视图刷新全部属性
    if pages.respond_to?(:selected_page=) && pg.respond_to?(:update)
      begin
        pages.selected_page = pg
        flags = 0
        Sketchup::Page.constants.each do |c|
          flags |= Sketchup::Page.const_get(c) if c.to_s.start_with?('PAGE_USE')
        end
        pg.update(flags) if flags > 0
      rescue => e
        puts "      page '#{name}' update 跳过: #{e.message}"
      end
    end
    pg
  end
  add_scene(pages, PAGES_ADD, 'SC-00-顶视图', make_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false))
  add_scene(pages, PAGES_ADD, 'SC-05-轴测', make_cam([c.x + diag*0.55, c.y - diag*0.55, bb.max.z + diag*0.45], [c.x, c.y, 0], [0, 0, 1], false))
  add_scene(pages, PAGES_ADD, 'SC-06-透视', make_cam([c.x + diag*0.4, c.y - diag*0.5, diag*0.3], [c.x, c.y, 50], [0, 0, 1], true))
rescue => e
  puts "scenes error: #{e.message}"
end

Dir.mkdir(EXPORT_DIR) unless File.directory?(EXPORT_DIR)
view = model.active_view
model.pages.each_with_index do |page, i|
  begin
    if model.pages.respond_to?(:selected_page=)
      model.pages.selected_page = page
    else
      view.camera = page.camera
    end
    f = File.join(EXPORT_DIR, format('%02d.png', i + 1))
    ok = view.write_image(filename: f, width: 1920, height: 1080, antialias: true)
    puts "export #{f}: #{ok}"
  rescue => e
    puts "export error: #{e.message}"
  end
end

begin
  model.save(OUT_SKP)
  puts "SAVED: #{OUT_SKP}"
rescue => e
  puts "SAVE FAILED: #{e.message}"
end
puts "BUILD DONE. 面数: #{model.entities.grep(Sketchup::Face).size}(顶层)  实体: #{model.entities.length}"
