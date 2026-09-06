# encoding: UTF-8
# ============================================================
# 拉塔皮住宅 Maison Latapie (Lacaton & Vassal, Floirac, 1993)
# 通过 MCP 桥执行: load 'C:/Users/muliz/.zcode/workspace/default/cad2skp/latapie.rb'
# 形制(依资料照片与图纸):
#   15m x 8m 两层体量; 街面(-Y)波纹钢板封闭 + 下层胶合板与蓝玻璃带;
#   花园面(+Y)全高园艺阳光房钢架(半透明膜/X拉索/大翻板门);
#   内部胶合板"盒子中的盒子", 前墙大玻璃门洞, 夹层; 上部开敞框架条带
# 单位: 米(API 内部英寸)
# ============================================================

LAT_SKP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/Latapie_v01.skp'
LAT_EXP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/exports'
LAT_M   = 39.3701
LAT_Z   = Geom::Vector3d.new(0, 0, 1)

def m1(v)
  v * LAT_M
end

model = Sketchup.active_model
begin
  model.entities.clear!
rescue
end
begin
  model.layers.purge_unused
  model.materials.purge_unused
rescue
end
begin
  model.pages.to_a.each { |p| model.pages.erase(p) }
rescue
end

%w[01-场地 02-基座 03-主体 04-阳光房 05-配景].each do |t|
  model.layers.add(t) if model.layers[t].nil?
end

def lat_mat(model, name, rgb, alpha = nil)
  m = model.materials[name]
  unless m
    m = model.materials.add(name)
    m.color = Sketchup::Color.new(*rgb)
    m.alpha = alpha if alpha
  end
  m
end

MAT_CONC  = lat_mat(model, 'MAT_基座_混凝土', [202, 200, 194])
MAT_PLY   = lat_mat(model, 'MAT_墙_胶合板',   [198, 150, 92])
MAT_CORR  = lat_mat(model, 'MAT_板_波纹钢',   [190, 194, 198])
MAT_STEEL = lat_mat(model, 'MAT_框_钢架',     [172, 176, 180])
MAT_GLASS = lat_mat(model, 'MAT_窗_玻璃',     [150, 180, 196], 0.45)
MAT_DARK  = lat_mat(model, 'MAT_窗_暗玻璃',   [44, 56, 70], 0.8)
MAT_FILM  = lat_mat(model, 'MAT_膜_半透明',   [238, 242, 238], 0.22)
MAT_PAVE  = lat_mat(model, 'MAT_地_地砖',     [212, 208, 200])
MAT_GRASS = lat_mat(model, 'MAT_地_草地',     [110, 134, 86])
MAT_LEAF  = lat_mat(model, 'MAT_树_树冠',     [86, 116, 70])
MAT_TRUNK = lat_mat(model, 'MAT_树_树干',     [96, 74, 56])

# 长方体(材质先设, 推拉后用预捕获边线上色侧面 —— 2026 pushpull 引用失效对策)
def lat_box(ents, mat, x1, y1, z1, x2, y2, z2)
  begin
    f = ents.add_face([x1, y1, z1], [x2, y1, z1], [x2, y2, z1], [x1, y2, z1])
    return nil unless f
    edges = f.edges
    f.material = mat; f.back_material = mat
    f.reverse! if f.normal.z < 0
    f.pushpull(z2 - z1)
    edges.each do |e|
      begin
        e.faces.each do |sf|
          next if sf.deleted?
          sf.material = mat; sf.back_material = mat
        end
      rescue
      end
    end
    f
  rescue => e
    puts "  box skip(#{x1.round(1)},#{y1.round(1)}): #{e.message}"
    nil
  end
end

# 平面内斜杆(X 拉索): 平行四边形面 -> 薄板
def lat_diag(ents, mat, x1, z1, x2, z2, y, thick)
  begin
    w = thick / 2.0
    f = ents.add_face([x1, y - w, z1], [x2, y - w, z2], [x2, y + w, z2], [x1, y + w, z1])
    return unless f
    n = f.normal
    f.pushpull(0.06)
    f.material = mat; f.back_material = mat
    f.edges.each do |e|
      begin
        e.faces.each do |sf|
          next if sf.deleted?
          sf.material = mat; sf.back_material = mat
        end
      rescue
      end
    end
  rescue => e
    puts "  diag skip: #{e.message}"
  end
end

def lat_cyl(ents, mat, x, y, z0, r, h)
  begin
    edges = ents.add_circle([x, y, z0], LAT_Z, r, 8)
    f = ents.add_face(edges)
    return unless f
    f.material = mat; f.back_material = mat
    f.reverse! if f.normal.z < 0
    f.pushpull(h)
    edges.each do |e|
      begin
        e.faces.each do |sf|
          next if sf.deleted?
          sf.material = mat; sf.back_material = mat
        end
      rescue
      end
    end
  rescue
  end
end

def lat_tree(ents, x, y, trunk_h, crown_r)
  lat_cyl(ents, MAT_TRUNK, x, y, 0, 0.18, trunk_h)
  lat_cyl(ents, MAT_LEAF, x, y, trunk_h - 1.4, crown_r, crown_r * 1.4)
  lat_cyl(ents, MAT_LEAF, x, y, trunk_h + crown_r * 1.0 - 1.0, crown_r * 0.6, crown_r * 1.0)
end

def lat_group(name, layer_name)
  g = Sketchup.active_model.entities.add_group
  g.name = name
  begin
    g.layer = Sketchup.active_model.layers[layer_name]
  rescue
  end
  g
end

puts '[1/6] 场地与基座...'
g_site = lat_group('GROUND', '01-场地')
lat_box(g_site.entities, MAT_GRASS, m1(-12), m1(-9), m1(-0.3), m1(27), m1(17), 0)
lat_box(g_site.entities, MAT_PAVE,  m1(-1),  m1(8),  m1(-0.05), m1(16), m1(12.5), m1(0.18))
g_base = lat_group('BASE', '02-基座')
lat_box(g_base.entities, MAT_CONC, m1(-0.25), m1(-0.25), 0, m1(15.25), m1(8.25), m1(0.2))

puts '[2/6] 主体胶合板盒子...'
g_house = lat_group('HOUSE', '03-主体')
# 主盒(后部)
lat_box(g_house.entities, MAT_PLY, m1(0), m1(0), m1(0.2), m1(15), m1(4.35), m1(5.6))
# 前墙壁柱(留 4 个大门洞)
[[0, 0.9], [3.4, 4.3], [6.8, 7.7], [10.2, 11.1], [13.6, 15]].each do |a, b|
  lat_box(g_house.entities, MAT_PLY, m1(a), m1(4.35), m1(0.2), m1(b), m1(4.6), m1(2.9))
end
lat_box(g_house.entities, MAT_PLY, m1(0), m1(4.35), m1(2.9), m1(15), m1(4.6), m1(3.3))
# 上层前墙(暗窗)
lat_box(g_house.entities, MAT_PLY, m1(0), m1(4.35), m1(3.3), m1(15), m1(4.6), m1(5.6))
[1.6, 4.6, 7.6, 10.6, 13.0].each do |x|
  lat_box(g_house.entities, MAT_DARK, m1(x), m1(4.55), m1(4.0), m1(x + 1.7), m1(4.62), m1(5.1))
end
# 夹层(透过玻璃门可见)
lat_box(g_house.entities, MAT_PLY, m1(0.3), m1(1.0), m1(2.9), m1(7.2), m1(4.2), m1(3.08))
# 街面下层蓝玻璃带
[0.7, 3.1, 5.5, 7.9, 10.3, 12.7].each do |x|
  lat_box(g_house.entities, MAT_GLASS, m1(x), m1(-0.02), m1(0.55), m1(x + 1.6), m1(0.06), m1(1.55))
end

puts '[3/6] 波纹钢板包覆(街面与屋面)...'
g_cor = lat_group('CORRUGATED', '03-主体')
lat_box(g_cor.entities, MAT_CORR, m1(-0.15), m1(-0.15), m1(1.8),  m1(15.15), m1(0.32), m1(5.9))
lat_box(g_cor.entities, MAT_CORR, m1(-0.15), m1(-0.15), m1(5.6),  m1(15.15), m1(4.7),  m1(5.78))
lat_box(g_cor.entities, MAT_CORR, m1(-0.15), m1(0.3),   m1(1.8),  m1(0.13),  m1(4.7),  m1(5.9))
lat_box(g_cor.entities, MAT_CORR, m1(14.87), m1(0.3),   m1(1.8),  m1(15.15), m1(4.7),  m1(5.9))

puts '[4/6] 阳光房钢架 + 半透明膜 + 拉索...'
g_serre = lat_group('SERRE', '04-阳光房')
# 花园面柱(7 根, 2.5m 间距)
0.upto(6) { |i| lat_box(g_serre.entities, MAT_STEEL, m1(i * 2.5), m1(7.88), m1(0.2), m1(i * 2.5 + 0.12), m1(8.0), m1(6.3)) }
# 侧柱
lat_box(g_serre.entities, MAT_STEEL, m1(0),    m1(4.55), m1(0.2), m1(0.12),  m1(8.0), m1(6.3))
lat_box(g_serre.entities, MAT_STEEL, m1(14.88), m1(4.55), m1(0.2), m1(15.0), m1(8.0), m1(6.3))
# 梁柱环梁(花园面顶/中, 侧顶/侧中)
lat_box(g_serre.entities, MAT_STEEL, m1(0),    m1(7.86), m1(6.25),  m1(15),    m1(8.0),  m1(6.42))
lat_box(g_serre.entities, MAT_STEEL, m1(0),    m1(7.86), m1(2.55),  m1(15),    m1(8.0),  m1(2.68))
lat_box(g_serre.entities, MAT_STEEL, m1(0),    m1(4.55), m1(6.25),  m1(0.15),  m1(8.0),  m1(6.42))
lat_box(g_serre.entities, MAT_STEEL, m1(14.85), m1(4.55), m1(6.25), m1(15.0),  m1(8.0),  m1(6.42))
lat_box(g_serre.entities, MAT_STEEL, m1(0),    m1(4.55), m1(2.55),  m1(0.15),  m1(8.0),  m1(2.68))
lat_box(g_serre.entities, MAT_STEEL, m1(14.85), m1(4.55), m1(2.55), m1(15.0),  m1(8.0),  m1(2.68))
# 屋顶上方开敞框架条带(立柱+纵梁)
[2.5, 7.5, 12.5].each do |x|
  lat_box(g_serre.entities, MAT_STEEL, m1(x - 0.07), m1(0.9), m1(5.78), m1(x + 0.07), m1(1.06), m1(6.42))
end
lat_box(g_serre.entities, MAT_STEEL, m1(0),  m1(0.86), m1(6.28), m1(15), m1(1.02), m1(6.42))
# 半透明膜(花园面整片 + 两侧 + 顶)
lat_box(g_serre.entities, MAT_FILM, m1(0.12), m1(7.9),  m1(0.3),  m1(14.88), m1(7.96), m1(6.22))
lat_box(g_serre.entities, MAT_FILM, m1(0.02), m1(4.62), m1(0.3),  m1(0.09),  m1(7.9),  m1(6.22))
lat_box(g_serre.entities, MAT_FILM, m1(14.91), m1(4.62), m1(0.3), m1(14.98), m1(7.9),  m1(6.22))
lat_box(g_serre.entities, MAT_FILM, m1(0.12), m1(4.6),  m1(6.28), m1(14.88), m1(7.9),  m1(6.38))
# X 拉索(花园面 3 组 + 两侧)
[[0.3, 2.5], [2.7, 4.9], [5.1, 7.3], [7.5, 9.7], [9.9, 12.3], [12.5, 14.7]].each do |a, b|
  lat_diag(g_serre.entities, MAT_STEEL, a, 0.5,  b, 6.1, 7.93, 0.05)
  lat_diag(g_serre.entities, MAT_STEEL, a, 6.1,  b, 0.5, 7.93, 0.05)
end
# 大翻板门(玻璃, 中央两樘)
lat_box(g_glaz_dummy = g_serre.entities, MAT_GLASS, m1(5.0), m1(7.5), m1(0.3), m1(7.4), m1(7.58), m1(2.5)) if false
[[4.3, 6.7], [8.3, 10.7]].each do |a, b|
  lat_box(g_serre.entities, MAT_GLASS, m1(a), m1(7.45), m1(0.3), m1(b), m1(7.62), m1(2.6))
end

puts '[5/6] 冬季花园地砖...'
lat_box(g_serre.entities, MAT_PAVE, m1(0.1), m1(4.7), m1(0.2), m1(14.9), m1(7.86), m1(0.3))

puts '[6/6] 配景与出图...'
g_land = lat_group('TREES', '05-配景')
[[-6, 12.5, 7, 2.6], [19.5, 11, 8, 3], [22, 15.5, 6.5, 2.4], [-7.5, -4, 7.5, 2.8], [20, -5.5, 7, 2.6]].each do |x, y, h, r|
  lat_tree(g_land.entities, m1(x), m1(y), h, r)
end

bb = model.bounds
c = bb.center
diag = bb.diagonal
puts "模型范围: #{bb.min} -> #{bb.max}"

pages = model.pages
begin
  pages.to_a.each { |p| pages.erase(p) }
rescue
end
PAGES_ADD = [:add_page, :add, :add_scene, :new_page].find { |m| pages.respond_to?(m) }

def lat_cam(eye, target, up, persp)
  begin
    return Sketchup::Camera.new(eye, target, up, persp)
  rescue
  end
  Sketchup::Camera.new(eye, target, up)
end

if PAGES_ADD
  begin
    view = model.active_view
    view.camera = lat_cam([c.x + diag*0.30, c.y + diag*0.34, diag*0.13], [c.x, c.y, m1(3)], [0, 0, 1], true)
    pages.send(PAGES_ADD, 'SC-01-花园透视')
    view.camera = lat_cam([c.x - diag*0.05, c.y - diag*0.34, diag*0.11], [c.x, c.y, m1(3)], [0, 0, 1], true)
    pages.send(PAGES_ADD, 'SC-02-街道透视')
    view.camera = lat_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false)
    pages.send(PAGES_ADD, 'SC-00-顶视图')
  rescue => e
    puts "scenes error: #{e.message}"
  end
end

Dir.mkdir(LAT_EXP) unless File.directory?(LAT_EXP)
view = model.active_view
LAT_VIEWS = [
  ['LT-01-花园透视', -> { lat_cam([c.x + diag*0.26, c.y + diag*0.30, diag*0.115], [c.x, c.y - m1(0.5), m1(2.8)], [0, 0, 1], true) }],
  ['LT-02-街道透视', -> { lat_cam([c.x - diag*0.04, c.y - diag*0.30, diag*0.10], [c.x, c.y, m1(2.8)], [0, 0, 1], true) }],
  ['LT-03-顶视图',   -> { lat_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false) }]
]
LAT_VIEWS.each do |name, mk|
  begin
    view.camera = mk.call
    f = File.join(LAT_EXP, "#{name}.png")
    ok = view.write_image(filename: f, width: 1920, height: 1080, antialias: true)
    puts "export #{f}: #{ok}"
  rescue => e
    puts "export error (#{name}): #{e.message}"
  end
end

begin
  model.save(LAT_SKP)
  puts "SAVED: #{LAT_SKP}"
rescue => e
  puts "SAVE FAILED: #{e.message}"
end
fc = 0
count_l = lambda do |ents|
  fc += ents.grep(Sketchup::Face).size
  ents.grep(Sketchup::Group).each { |g| count_l.call(g.entities) }
  ents.grep(Sketchup::ComponentInstance).each { |ci| count_l.call(ci.definition.entities) }
end
count_l.call(model.entities)
puts "LAT BUILD DONE. 面数: #{fc}  实体: #{model.entities.length}"
