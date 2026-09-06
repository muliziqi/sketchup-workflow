# encoding: UTF-8
# ============================================================
# 流水别墅 Fallingwater (F.L. Wright, 1935) 体块模型
# 通过 MCP 桥执行: load 'C:/Users/muliz/.zcode/workspace/default/cad2skp/fallingwater.rb'
# 要素: 溪流+瀑布+岩石场地 / 四层奶油色混凝土挑板 / 竖向砂岩墙体 /
#       大玻璃面 / 樱桃红窗楣 / 南向大挑台 / 客舍+连廊 / 树木配景
# 单位: 英尺(API 内部英寸), 坐标: X=顺溪向(上游+X), Y=跨溪向(南为-Y), Z=向上
# ============================================================

FW_SKP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/Fallingwater_v01.skp'
FW_EXP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/exports'
FT = 12.0
FW_Z = Geom::Vector3d.new(0, 0, 1)

model = Sketchup.active_model
begin
  model.entities.clear!
  model.definitions.to_a.each { |d| model.definitions.remove(d) if d.instances.empty? }
rescue => e
  puts "clear: #{e.message}"
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

%w[01-场地 02-楼板 03-墙体 04-门窗 05-配景].each do |t|
  model.layers.add(t) if model.layers[t].nil?
end

def fw_mat(model, name, rgb, alpha = nil)
  m = model.materials[name]
  unless m
    m = model.materials.add(name)
    m.color = Sketchup::Color.new(*rgb)
    m.alpha = alpha if alpha
  end
  m
end

MAT_SLAB  = fw_mat(model, 'MAT_板_奶油黄', [226, 208, 168])
MAT_STONE = fw_mat(model, 'MAT_墙_砂岩',   [142, 126, 104])
MAT_GLASS = fw_mat(model, 'MAT_窗_玻璃',   [168, 200, 214], 0.35)
MAT_RED   = fw_mat(model, 'MAT_框_樱桃红', [128, 44, 34])
MAT_WATER = fw_mat(model, 'MAT_水_溪流',   [96, 140, 160], 0.7)
MAT_ROCK  = fw_mat(model, 'MAT_石_卵石',   [120, 116, 110])
MAT_GRASS = fw_mat(model, 'MAT_地_草地',   [104, 128, 82])
MAT_LEAF  = fw_mat(model, 'MAT_树_树冠',   [78, 108, 64])
MAT_TRUNK = fw_mat(model, 'MAT_树_树干',   [96, 74, 56])

def fw_ft(v)
  v * 12.0
end

# 长方体: 底面 z1 四角 -> 推拉到 z2, 全面上色
# 注意: pushpull 后原面引用会失效, 材质必须在推拉前设置, 侧面上色用提前捕获的边线
def fw_box(ents, mat, x1, y1, z1, x2, y2, z2)
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
    puts "  box skip(#{x1.round},#{y1.round}): #{e.message}"
    nil
  end
end

# 圆柱(树干/树冠)
def fw_cyl(ents, mat, x, y, z0, r, h)
  begin
    edges = ents.add_circle([x, y, z0], FW_Z, r, 8)
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
  rescue => e
    puts "  cyl skip: #{e.message}"
  end
end

def fw_tree(ents, x, y, trunk_h, crown_r)
  fw_cyl(ents, MAT_TRUNK, x, y, 0, 0.45*12, trunk_h*12)
  fw_cyl(ents, MAT_LEAF, x, y, trunk_h*12 - 18, crown_r*12, crown_r*12*1.5)
  fw_cyl(ents, MAT_LEAF, x, y, (trunk_h + crown_r*1.1)*12 - 6, crown_r*0.62*12, crown_r*12*1.1)
end

def fw_group(name, layer_name)
  g = Sketchup.active_model.entities.add_group
  g.name = name
  begin
    g.layer = Sketchup.active_model.layers[layer_name]
  rescue
  end
  g
end

puts '[1/6] 场地: 地形/溪流/瀑布/岩石...'
g_site = fw_group('SITE', '01-场地')
# 草地(避开溪道 y[-12,12])
fw_box(g_site.entities, MAT_GRASS, fw_ft(-130), fw_ft(12),  fw_ft(-10), fw_ft(130), fw_ft(90),  fw_ft(-9.3))
fw_box(g_site.entities, MAT_GRASS, fw_ft(-130), fw_ft(-90), fw_ft(-10), fw_ft(130), fw_ft(-12), fw_ft(-9.3))
fw_box(g_site.entities, MAT_GRASS, fw_ft(-130), fw_ft(-12), fw_ft(-10), fw_ft(-120), fw_ft(12), fw_ft(-9.3))
fw_box(g_site.entities, MAT_GRASS, fw_ft(120),  fw_ft(-12), fw_ft(-10), fw_ft(130), fw_ft(12),  fw_ft(-9.3))
# 溪床 + 上游水面(接近首层地面) + 跌水 + 下游水面
fw_box(g_site.entities, MAT_ROCK,  fw_ft(-120), fw_ft(-12), fw_ft(-10), fw_ft(120), fw_ft(12), fw_ft(-9.6))
fw_box(g_site.entities, MAT_WATER, fw_ft(1),    fw_ft(-12), fw_ft(-2),  fw_ft(120), fw_ft(12), fw_ft(-1))
fw_box(g_site.entities, MAT_WATER, fw_ft(-120), fw_ft(-12), fw_ft(-10), fw_ft(-0.5), fw_ft(12), fw_ft(-9))
fw_box(g_site.entities, MAT_WATER, fw_ft(-0.6), fw_ft(-12), fw_ft(-9),  fw_ft(0),   fw_ft(12), fw_ft(-1))
# 别墅基座岩盘(上游侧)
fw_box(g_site.entities, MAT_ROCK,  fw_ft(0.5),  fw_ft(-14), fw_ft(-10), fw_ft(32), fw_ft(12), fw_ft(-1))
# 跌水口卵石堆
fw_box(g_site.entities, MAT_ROCK,  fw_ft(-7),  fw_ft(-9),  fw_ft(-10), fw_ft(-1), fw_ft(-2), fw_ft(-5))
fw_box(g_site.entities, MAT_ROCK,  fw_ft(2),   fw_ft(-6),  fw_ft(-10), fw_ft(8),  fw_ft(2),  fw_ft(-6))
fw_box(g_site.entities, MAT_ROCK,  fw_ft(-5),  fw_ft(3),   fw_ft(-10), fw_ft(3),  fw_ft(8),  fw_ft(-4.5))
fw_box(g_site.entities, MAT_ROCK,  fw_ft(6),   fw_ft(-11), fw_ft(-10), fw_ft(12), fw_ft(-6), fw_ft(-5))
fw_box(g_site.entities, MAT_ROCK,  fw_ft(-11), fw_ft(-11), fw_ft(-10), fw_ft(-6), fw_ft(-6), fw_ft(-4.5))
fw_box(g_site.entities, MAT_ROCK,  fw_ft(30),  fw_ft(-8),  fw_ft(-2),  fw_ft(37), fw_ft(-1), fw_ft(0.4))
fw_box(g_site.entities, MAT_ROCK,  fw_ft(48),  fw_ft(4),   fw_ft(-2),  fw_ft(55), fw_ft(10), fw_ft(0.2))

puts '[2/6] 混凝土挑板(四层)...'
g_slab = fw_group('SLABS', '02-楼板')
# 主卧层 L1 楼板 + 南主挑台 + 矮墙
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-24), fw_ft(-20), fw_ft(-1),  fw_ft(30),  fw_ft(12),  fw_ft(0))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-16), fw_ft(-32), fw_ft(-1),  fw_ft(18),  fw_ft(-20), fw_ft(0))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-16), fw_ft(-32.8), fw_ft(0), fw_ft(18), fw_ft(-32), fw_ft(3.5))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-16.8), fw_ft(-32), fw_ft(0), fw_ft(-16), fw_ft(-20), fw_ft(3.5))
# 卧室层 L2 楼板(南挑 30ft)+ 矮墙
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-28), fw_ft(-30), fw_ft(9),   fw_ft(26),  fw_ft(12),  fw_ft(10))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-28), fw_ft(-30.8), fw_ft(10), fw_ft(8), fw_ft(-30), fw_ft(13.5))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(25.2), fw_ft(-30), fw_ft(10), fw_ft(26), fw_ft(-16), fw_ft(13.5))
# 书房层 L3 楼板(南挑)+ 矮墙
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-16), fw_ft(-24), fw_ft(19),  fw_ft(18),  fw_ft(8),   fw_ft(20))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-16), fw_ft(-24.8), fw_ft(20), fw_ft(12), fw_ft(-24), fw_ft(23.5))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(-16.8), fw_ft(-24), fw_ft(20), fw_ft(-16), fw_ft(-12), fw_ft(23.5))
# 客舍楼板 + 连廊板及矮墙
fw_box(g_slab.entities, MAT_SLAB, fw_ft(42),  fw_ft(2),   fw_ft(-1),  fw_ft(68),  fw_ft(26),  fw_ft(0))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(44),  fw_ft(4),   fw_ft(9),   fw_ft(66),  fw_ft(24),  fw_ft(10))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(26),  fw_ft(6),   fw_ft(9),   fw_ft(42),  fw_ft(12),  fw_ft(10))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(26),  fw_ft(5.2), fw_ft(10),  fw_ft(42),  fw_ft(6),   fw_ft(13))
fw_box(g_slab.entities, MAT_SLAB, fw_ft(26),  fw_ft(12),  fw_ft(10),  fw_ft(42),  fw_ft(12.8), fw_ft(13))

puts '[3/6] 砂岩墙体与壁炉烟囱...'
g_wall = fw_group('WALLS', '03-墙体')
fw_box(g_wall.entities, MAT_STONE, fw_ft(-10), fw_ft(-6),  fw_ft(0),   fw_ft(-2),  fw_ft(10),  fw_ft(30))
fw_box(g_wall.entities, MAT_STONE, fw_ft(-24), fw_ft(10),  fw_ft(0),   fw_ft(30),  fw_ft(12),  fw_ft(9))
fw_box(g_wall.entities, MAT_STONE, fw_ft(20),  fw_ft(-10), fw_ft(0),   fw_ft(30),  fw_ft(10),  fw_ft(8.5))
fw_box(g_wall.entities, MAT_STONE, fw_ft(-24), fw_ft(-8),  fw_ft(0),   fw_ft(-16), fw_ft(10),  fw_ft(8.5))
fw_box(g_wall.entities, MAT_STONE, fw_ft(-28), fw_ft(-4),  fw_ft(10),  fw_ft(-10), fw_ft(12),  fw_ft(18))
fw_box(g_wall.entities, MAT_STONE, fw_ft(6),   fw_ft(2),   fw_ft(10),  fw_ft(26),  fw_ft(12),  fw_ft(18))
fw_box(g_wall.entities, MAT_STONE, fw_ft(-10), fw_ft(10),  fw_ft(10),  fw_ft(6),   fw_ft(12),  fw_ft(18))
fw_box(g_wall.entities, MAT_STONE, fw_ft(2),   fw_ft(-4),  fw_ft(20),  fw_ft(18),  fw_ft(8),   fw_ft(27))
fw_box(g_wall.entities, MAT_STONE, fw_ft(-16), fw_ft(-12), fw_ft(20),  fw_ft(-6),  fw_ft(8),   fw_ft(27))
fw_box(g_wall.entities, MAT_STONE, fw_ft(-8),  fw_ft(-6),  fw_ft(27),  fw_ft(4),   fw_ft(6),   fw_ft(30))
fw_box(g_wall.entities, MAT_STONE, fw_ft(44),  fw_ft(4),   fw_ft(0),   fw_ft(66),  fw_ft(24),  fw_ft(9))
fw_box(g_wall.entities, MAT_STONE, fw_ft(46),  fw_ft(6),   fw_ft(10),  fw_ft(60),  fw_ft(22),  fw_ft(16))
# 支撑挑台的石墩(没入水中)
fw_box(g_wall.entities, MAT_STONE, fw_ft(-2),  fw_ft(-27), fw_ft(-9),  fw_ft(2),   fw_ft(-23), fw_ft(9))
fw_box(g_wall.entities, MAT_STONE, fw_ft(10),  fw_ft(-27), fw_ft(-9),  fw_ft(14),  fw_ft(-23), fw_ft(9))
fw_box(g_wall.entities, MAT_STONE, fw_ft(22),  fw_ft(-27), fw_ft(-9),  fw_ft(26),  fw_ft(-23), fw_ft(9))
fw_box(g_wall.entities, MAT_STONE, fw_ft(32),  fw_ft(7),   fw_ft(-9),  fw_ft(35),  fw_ft(11),  fw_ft(9))

puts '[4/6] 玻璃与樱桃红窗楣...'
g_glaz = fw_group('GLASS', '04-门窗')
fw_box(g_glaz.entities, MAT_GLASS, fw_ft(-8),   fw_ft(-20),  fw_ft(0),    fw_ft(19),  fw_ft(-19.5), fw_ft(8.5))
fw_box(g_glaz.entities, MAT_GLASS, fw_ft(-4),   fw_ft(-6),   fw_ft(10.5), fw_ft(22),  fw_ft(4),     fw_ft(17.5))
fw_box(g_glaz.entities, MAT_GLASS, fw_ft(-6),   fw_ft(-12),  fw_ft(20.5), fw_ft(12),  fw_ft(-10),   fw_ft(26.5))
fw_box(g_glaz.entities, MAT_GLASS, fw_ft(-23.7),fw_ft(-8),   fw_ft(0),    fw_ft(-23.3), fw_ft(10),  fw_ft(8.5))
fw_box(g_glaz.entities, MAT_GLASS, fw_ft(44),   fw_ft(4.3),  fw_ft(1),    fw_ft(66),  fw_ft(4.7),   fw_ft(8))
fw_box(g_glaz.entities, MAT_GLASS, fw_ft(19.7), fw_ft(-19.5),fw_ft(0),    fw_ft(20.3), fw_ft(12),   fw_ft(8.5))
# 樱桃红窗楣(挑板前缘色带)
fw_box(g_glaz.entities, MAT_RED,   fw_ft(-24),  fw_ft(-20.4), fw_ft(-0.35), fw_ft(30), fw_ft(-20), fw_ft(-0.05))
fw_box(g_glaz.entities, MAT_RED,   fw_ft(-28),  fw_ft(-30.4), fw_ft(9),     fw_ft(8),  fw_ft(-30), fw_ft(9.3))
fw_box(g_glaz.entities, MAT_RED,   fw_ft(-16),  fw_ft(-24.4), fw_ft(19),    fw_ft(12), fw_ft(-24), fw_ft(19.3))

puts '[5/6] 树木配景...'
g_land = fw_group('TREES', '05-配景')
[[-70, 50, 14, 6], [-50, -45, 16, 7], [-30, 55, 12, 5], [50, 50, 15, 6], [75, 22, 12, 5],
 [-95, 25, 14, 6], [90, -40, 16, 7], [-20, -60, 13, 6], [60, -55, 15, 6], [105, 12, 14, 5],
 [-100, -40, 15, 7], [20, 60, 13, 5]].each do |x, y, h, r|
  fw_tree(g_land.entities, fw_ft(x), fw_ft(y), h, r)
end

puts '[6/6] 场景与出图...'
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

def fw_cam(eye, target, up, persp)
  begin
    return Sketchup::Camera.new(eye, target, up, persp)
  rescue
  end
  Sketchup::Camera.new(eye, target, up)
end

def fw_scene(pages, method, name, cam)
  view = Sketchup.active_model.active_view
  view.camera = cam
  view.zoom_extents
  pg = pages.send(method, name)
  begin
    pg.use_camera = true
  rescue
  end
  pg
end

if PAGES_ADD
  begin
    fw_scene(pages, PAGES_ADD, 'SC-01-东南透视', fw_cam(
      [c.x + diag*0.38, c.y - diag*0.42, diag*0.16], [c.x, c.y, fw_ft(8)], [0, 0, 1], true))
    fw_scene(pages, PAGES_ADD, 'SC-02-西南透视', fw_cam(
      [c.x - diag*0.30, c.y - diag*0.48, diag*0.14], [c.x, c.y + fw_ft(5), fw_ft(10)], [0, 0, 1], true))
    fw_scene(pages, PAGES_ADD, 'SC-00-顶视图', fw_cam(
      [c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false))
  rescue => e
    puts "scenes error: #{e.message}"
  end
end

Dir.mkdir(FW_EXP) unless File.directory?(FW_EXP)
view = model.active_view
FW_VIEWS = [
  ['FW-01-东南透视', -> { fw_cam([c.x + diag*0.38, c.y - diag*0.42, diag*0.16], [c.x, c.y, fw_ft(8)], [0, 0, 1], true) }],
  ['FW-02-西南透视', -> { fw_cam([c.x - diag*0.30, c.y - diag*0.48, diag*0.14], [c.x, c.y + fw_ft(5), fw_ft(10)], [0, 0, 1], true) }],
  ['FW-03-顶视图',   -> { fw_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false) }]
]
FW_VIEWS.each do |name, mk|
  begin
    view.camera = mk.call
    view.zoom_extents
    f = File.join(FW_EXP, "#{name}.png")
    ok = view.write_image(filename: f, width: 1920, height: 1080, antialias: true)
    puts "export #{f}: #{ok}"
  rescue => e
    puts "export error (#{name}): #{e.message}"
  end
end

begin
  model.save(FW_SKP)
  puts "SAVED: #{FW_SKP}"
rescue => e
  puts "SAVE FAILED: #{e.message}"
end
fc = 0
count_f = lambda do |ents|
  fc += ents.grep(Sketchup::Face).size
  ents.grep(Sketchup::Group).each { |g| count_f.call(g.entities) }
  ents.grep(Sketchup::ComponentInstance).each { |ci| count_f.call(ci.definition.entities) }
end
count_f.call(model.entities)
puts "FW BUILD DONE. 面数: #{fc}  实体: #{model.entities.length}"
