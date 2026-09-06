# encoding: UTF-8
# ============================================================
# 拉塔皮住宅 Maison Latapie v2 —— 依图纸 PDF 重建(尺寸实测于 1:100 图)
# 平面: 12.0m(宽) x 12.6m(深); 街面(Y=0)为低檐端, 花园面(Y=12.6)为高檐端
# 单坡屋面: 檐口 4.7m(街) -> 6.5m(花园); 主体两层在西侧(深 5.3m),
#           东侧 7.3m 通高 SERRE 冬季花园(钢架+半透明膜+玻璃翻板门+X拉索)
# 首层: (GARAGE)+厨卫楼梯核心+SEJOUR; 二层: 两间卧室+卫生间(卧室窗朝阳光房)
# 执行: MCP 桥 eval -> load 本文件; 保存 Latapie_v02.skp
# ============================================================

LAT2_SKP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/Latapie_v02.skp'
LAT2_EXP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/exports'
LAT2_M   = 39.3701
LAT2_Z   = Geom::Vector3d.new(0, 0, 1)

def m2(v)
  v * LAT2_M
end

def m1(v)
  v * LAT2_M
end

model = Sketchup.active_model
begin
  model.entities.clear!
  model.definitions.to_a.each { |d| model.definitions.remove(d) if d.instances.empty? }
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

def lat2_mat(model, name, rgb, alpha = nil)
  m = model.materials[name]
  unless m
    m = model.materials.add(name)
    m.color = Sketchup::Color.new(*rgb)
    m.alpha = alpha if alpha
  end
  m
end

MAT_CONC  = lat2_mat(model, 'MAT_基座_混凝土', [202, 200, 194])
MAT_PLY   = lat2_mat(model, 'MAT_墙_胶合板',   [198, 150, 92])
MAT_CORR  = lat2_mat(model, 'MAT_板_波纹钢',   [190, 194, 198])
MAT_STEEL = lat2_mat(model, 'MAT_框_钢架',     [172, 176, 180])
MAT_GLASS = lat2_mat(model, 'MAT_窗_玻璃',     [150, 180, 196], 0.45)
MAT_DARK  = lat2_mat(model, 'MAT_窗_暗玻璃',   [44, 56, 70], 0.8)
MAT_FILM  = lat2_mat(model, 'MAT_膜_半透明',   [238, 242, 238], 0.22)
MAT_PAVE  = lat2_mat(model, 'MAT_地_地砖',     [212, 208, 200])
MAT_GRASS = lat2_mat(model, 'MAT_地_草地',     [110, 134, 86])
MAT_LEAF  = lat2_mat(model, 'MAT_树_树冠',     [86, 116, 70])
MAT_TRUNK = lat2_mat(model, 'MAT_树_树干',     [96, 74, 56])

def lat2_box(ents, mat, x1, y1, z1, x2, y2, z2)
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
    puts "  box skip: #{e.message}"
    nil
  end
end

# 任意 4 点平面 + 沿法线推拉(用于梯形墙/斜屋面)
def lat2_plate(ents, mat, p1, p2, p3, p4, thick)
  begin
    pts = [p1, p2, p3, p4]
    f = ents.add_face(p1, p2, p3, p4)
    return nil unless f
    edges = f.edges
    f.material = mat; f.back_material = mat
    n = f.normal
    f.reverse! if n.z < 0 && n.x.abs < 0.9 # 水平面朝上; 竖面/斜面保持法线向外
    d = thick
    d = -d if f.normal.z > 0.9 && pts[0][2] == pts[1][2] && pts[0][2] > 0 # 顶面板向下
    f.pushpull(d)
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
    puts "  plate skip: #{e.message}"
    nil
  end
end

def lat2_cyl(ents, mat, x, y, z0, r, h)
  begin
    edges = ents.add_circle([x, y, z0], LAT2_Z, r, 8)
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

def lat2_tree(ents, x, y, trunk_h, crown_r)
  lat2_cyl(ents, MAT_TRUNK, x, y, 0, 0.18, trunk_h)
  lat2_cyl(ents, MAT_LEAF, x, y, trunk_h - 1.4, crown_r, crown_r * 1.4)
  lat2_cyl(ents, MAT_LEAF, x, y, trunk_h + crown_r - 0.8, crown_r * 0.6, crown_r)
end

def lat2_group(name, layer_name)
  g = Sketchup.active_model.entities.add_group
  g.name = name
  begin
    g.layer = Sketchup.active_model.layers[layer_name]
  rescue
  end
  g
end

puts '[1/7] 场地与基座...'
g_site = lat2_group('GROUND', '01-场地')
lat2_box(g_site.entities, MAT_GRASS, m2(-10), m2(-8), m2(-0.3), m2(22), m2(18), 0)
lat2_box(g_site.entities, MAT_PAVE,  m2(-1.6), m2(-3.2), m2(-0.05), m2(13.6), m2(0.05), m2(0.15))
g_base = lat2_group('BASE', '02-基座')
lat2_box(g_base.entities, MAT_CONC, m2(-0.25), m2(-0.25), 0, m2(12.25), m2(12.85), m2(0.2))

puts '[2/7] 主体楔形体量(单坡, 檐口 4.7 -> 5.5)...'
g_house = lat2_group('HOUSE', '03-主体')
# 楔形主体: X=0 剖面梯形, 沿 X 推拉 12m
lat2_plate(g_house.entities, MAT_PLY,
  [m2(0), m2(0), m2(0.2)], [m2(0), m2(5.3), m2(0.2)],
  [m2(0), m2(5.3), m2(5.5)], [m2(0), m2(0), m2(4.7)], m2(12))
# 冬季花园方向前墙: 玻璃推拉门(首层) + 百叶窗(二层)
lat2_plate(g_house.entities, MAT_PLY,
  [m2(0), m2(5.05), m2(0.2)], [m2(12), m2(5.05), m2(0.2)],
  [m2(12), m2(5.05), m2(5.5)], [m2(0), m2(5.05), m2(4.7)], m2(0.25))
[1.2, 3.9, 6.6, 9.3].each do |x|
  lat2_box(g_house.entities, MAT_GLASS, m2(x), m2(5.28), m2(0.35), m2(x + 2.0), m2(5.34), m2(2.75))
end
[1.0, 3.7, 6.4, 9.1].each do |x|
  lat2_box(g_house.entities, MAT_DARK, m2(x), m2(5.28), m2(3.5), m2(x + 2.0), m2(5.34), m2(4.9))
end
# 街面(Y=0): 蓝玻璃带(推拉门版面)
[0.7, 3.1, 5.5, 7.9, 10.3].each do |x|
  lat2_box(g_house.entities, MAT_GLASS, m2(x), m2(-0.02), m2(0.55), m2(x + 1.6), m2(0.04), m2(1.55))
end
# 室内核心(厨卫楼梯) + 夹层
lat2_box(g_house.entities, MAT_PLY, m2(4.0), m2(1.0), m2(0.2), m2(6.8), m2(3.4), m2(2.85))
lat2_box(g_house.entities, MAT_PLY, m2(0.3), m2(0.4), m2(2.85), m2(6.8), m2(4.9), m2(3.05))

puts '[3/7] 街面波纹钢板 + 单坡屋面...'
g_cor = lat2_group('CORRUGATED', '03-主体')
# 街面波纹钢板(上缘随坡)
lat2_plate(g_cor.entities, MAT_CORR,
  [m2(-0.15), m2(-0.15), m2(1.4)], [m2(-0.15), m2(0.4), m2(1.4)],
  [m2(-0.15), m2(0.4), m2(4.62)], [m2(-0.15), m2(-0.15), m2(4.55)], m2(0.45))
# 单坡屋面板(整片, 檐口 4.72 -> 6.55, 出檐 0.3)
lat2_plate(g_cor.entities, MAT_CORR,
  [m2(-0.3), m2(-0.3), m2(4.72)], [m2(12.3), m2(-0.3), m2(4.72)],
  [m2(12.3), m2(12.9), m2(6.55)], [m2(-0.3), m2(12.9), m2(6.55)], m2(0.12))
# 侧面包覆(随坡, 简化为两段)
lat2_plate(g_cor.entities, MAT_CORR,
  [m2(-0.15), m2(0.35), m2(1.8)], [m2(0.13), m2(0.35), m2(1.8)],
  [m2(0.13), m2(0.35), m2(4.6)], [m2(-0.15), m2(0.35), m2(4.6)], m2(0.0) + 0.28)

puts '[4/7] 阳光房: 钢架/膜/翻板门/拉索...'
g_serre = lat2_group('SERRE', '04-阳光房')
# 花园面(E) 7 柱
0.upto(6) { |i| lat2_box(g_serre.entities, MAT_STEEL, m2(i * 2.0), m2(12.45), m2(0.2), m2(i * 2.0 + 0.12), m2(12.6), m2(6.3)) }
# 顶/中/底梁
lat2_box(g_serre.entities, MAT_STEEL, m2(0),    m2(12.42), m2(6.22), m2(12),   m2(12.6),  m2(6.38))
lat2_box(g_serre.entities, MAT_STEEL, m2(0),    m2(12.42), m2(2.52), m2(12),   m2(12.6),  m2(2.66))
lat2_box(g_serre.entities, MAT_STEEL, m2(0),    m2(12.42), m2(0.2),  m2(12),   m2(12.6),  m2(0.34))
# 侧柱与侧梁(南北两侧的阳光房边框)
lat2_box(g_serre.entities, MAT_STEEL, m2(0),     m2(5.28), m2(0.2),  m2(0.12),  m2(12.6), m2(6.3))
lat2_box(g_serre.entities, MAT_STEEL, m2(11.88), m2(5.28), m2(0.2),  m2(12.0),  m2(12.6), m2(6.3))
lat2_box(g_serre.entities, MAT_STEEL, m2(0),     m2(5.3),  m2(2.52), m2(0.12),  m2(12.5), m2(2.66))
lat2_box(g_serre.entities, MAT_STEEL, m2(11.88), m2(5.3),  m2(2.52), m2(12.0),  m2(12.5), m2(2.66))
lat2_box(g_serre.entities, MAT_STEEL, m2(0),     m2(5.3),  m2(4.55), m2(0.12),  m2(12.5), m2(4.68))
lat2_box(g_serre.entities, MAT_STEEL, m2(11.88), m2(5.3),  m2(4.55), m2(12.0),  m2(12.5), m2(4.68))
# 膜: 花园面整片 + 两侧 + 顶(屋面下的水平膜带)
lat2_box(g_serre.entities, MAT_FILM, m2(0.14),  m2(12.47), m2(0.36), m2(11.86), m2(12.52), m2(6.2))
lat2_box(g_serre.entities, MAT_FILM, m2(0.02),  m2(5.4),   m2(0.36), m2(0.08),  m2(12.42), m2(6.2))
lat2_box(g_serre.entities, MAT_FILM, m2(11.92), m2(5.4),   m2(0.36), m2(11.98), m2(12.42), m2(6.2))
# 中段膜(柱间) + 顶段玻璃窗带
lat2_box(g_serre.entities, MAT_FILM,  m2(0.16), m2(12.44), m2(2.7),  m2(11.84), m2(12.5),  m2(4.25))
lat2_box(g_serre.entities, MAT_GLASS, m2(0.18), m2(12.44), m2(4.32), m2(11.82), m2(12.5),  m2(5.95))
# 首层玻璃翻板门(6 樘)
[0.15, 2.05, 3.95, 5.85, 7.75, 9.65].each do |a|
  lat2_box(g_serre.entities, MAT_GLASS, m2(a), m2(12.42), m2(0.36), m2(a + 1.8), m2(12.5), m2(2.45))
end
# X 拉索(花园面 3 组)
[[0.3, 3.9], [4.1, 7.9], [8.1, 11.7]].each do |a, b|
  lat2_plate(g_serre.entities, MAT_STEEL,
    [m2(a), m2(12.44), m2(0.6)], [m2(b), m2(12.44), m2(5.9)],
    [m2(b), m2(12.44), m2(6.05)], [m2(a), m2(12.44), m2(0.75)], 0.06)
  lat2_plate(g_serre.entities, MAT_STEEL,
    [m2(a), m2(12.44), m2(5.9)], [m2(b), m2(12.44), m2(0.6)],
    [m2(b), m2(12.44), m2(0.75)], [m2(a), m2(12.44), m2(6.05)], 0.06)
end
# 冬季花园地砖
lat2_box(g_serre.entities, MAT_PAVE, m2(0.1), m2(5.32), m2(0.2), m2(11.9), m2(12.42), m2(0.3))

puts '[5/7] 屋面开敞通风带(住宅屋面与阳光房顶之间)...'
# 依北立面: 主体上方保留开敞框架条带(立柱已在阳光房组, 此处补两根横梁)
[0.5, 6.0, 11.5].each do |x|
  lat2_box(g_serre.entities, MAT_STEEL, m2(x - 0.07), m2(4.9), m2(5.62), m2(x + 0.07), m2(5.06), m2(6.3))
end

puts '[6/7] 配景...'
g_land = lat2_group('TREES', '05-配景')
[[-5, 4, 7, 2.6], [16, 8, 8, 3], [18.5, 14, 6.5, 2.4], [-6.5, 14, 7.5, 2.8], [5, 16.5, 7, 2.6], [16, -6, 7, 2.6]].each do |x, y, h, r|
  lat2_tree(g_land.entities, m2(x), m2(y), h, r)
end

puts '[7/7] 场景与出图...'
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

def lat2_cam(eye, target, up, persp)
  begin
    return Sketchup::Camera.new(eye, target, up, persp)
  rescue
  end
  Sketchup::Camera.new(eye, target, up)
end

if PAGES_ADD
  begin
    view = model.active_view
    view.camera = lat2_cam([c.x + diag*0.34, c.y + diag*0.40, diag*0.15], [c.x, c.y, m2(3)], [0, 0, 1], true)
    pages.send(PAGES_ADD, 'SC-01-花园透视')
    view.camera = lat2_cam([c.x + diag*0.05, c.y - diag*0.36, diag*0.12], [c.x, c.y, m2(2.8)], [0, 0, 1], true)
    pages.send(PAGES_ADD, 'SC-02-街道透视')
    view.camera = lat2_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false)
    pages.send(PAGES_ADD, 'SC-00-顶视图')
  rescue => e
    puts "scenes error: #{e.message}"
  end
end

Dir.mkdir(LAT2_EXP) unless File.directory?(LAT2_EXP)
view = model.active_view
LAT2_VIEWS = [
  ['LT2-01-花园透视', -> { lat2_cam([c.x + diag*0.34, c.y + diag*0.40, diag*0.15], [c.x, c.y, m2(3)], [0, 0, 1], true) }],
  ['LT2-02-街道透视', -> { lat2_cam([c.x + diag*0.05, c.y - diag*0.36, diag*0.12], [c.x, c.y, m2(2.8)], [0, 0, 1], true) }],
  ['LT2-03-侧透视',   -> { lat2_cam([c.x - diag*0.36, c.y + diag*0.02, diag*0.10], [c.x, c.y, m2(3)], [0, 0, 1], true) }],
  ['LT2-04-顶视图',   -> { lat2_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false) }]
]
LAT2_VIEWS.each do |name, mk|
  begin
    view.camera = mk.call
    f = File.join(LAT2_EXP, "#{name}.png")
    ok = view.write_image(filename: f, width: 1920, height: 1080, antialias: true)
    puts "export #{f}: #{ok}"
  rescue => e
    puts "export error (#{name}): #{e.message}"
  end
end

begin
  model.save(LAT2_SKP)
  puts "SAVED: #{LAT2_SKP}"
rescue => e
  puts "SAVE FAILED: #{e.message}"
end
fc = 0
count_l2 = lambda do |ents|
  fc += ents.grep(Sketchup::Face).size
  ents.grep(Sketchup::Group).each { |g| count_l2.call(g.entities) }
  ents.grep(Sketchup::ComponentInstance).each { |ci| count_l2.call(ci.definition.entities) }
end
count_l2.call(model.entities)
puts "LAT2 BUILD DONE. 面数: #{fc}  实体: #{model.entities.length}"
