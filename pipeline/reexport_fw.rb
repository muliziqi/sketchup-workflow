# encoding: UTF-8
# 流水别墅模型精修: 树木落地 + 相机拉近重出图
FT = 12.0
FW_EXP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/exports'
FW_SKP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/Fallingwater_v01.skp'
FW_Z = Geom::Vector3d.new(0, 0, 1)

model = Sketchup.active_model
bb = model.bounds
c = bb.center
diag = bb.diagonal

# 1. 树木落地: TREES 组平移到草皮表面(-9.3ft)
trees = model.entities.grep(Sketchup::Group).find { |g| g.name == 'TREES' }
if trees
  tz = trees.bounds.min.z
  delta = -9.3 * FT + 6 - tz
  trees.transform!(Geom::Transformation.translation([0, 0, delta]))
  puts "trees moved: #{delta.round}"
end

def fw_cam(eye, target, up, persp)
  begin
    return Sketchup::Camera.new(eye, target, up, persp)
  rescue
  end
  Sketchup::Camera.new(eye, target, up)
end

# 2. 相机拉近(不调 zoom_extents, 保持取景)
view = model.active_view
VIEWS2 = [
  ['FW-01-东南透视', -> { fw_cam([c.x + diag*0.20, c.y - diag*0.26, diag*0.11], [c.x, c.y, fw_ft(9)], [0, 0, 1], true) }],
  ['FW-02-西南透视', -> { fw_cam([c.x - diag*0.15, c.y - diag*0.30, diag*0.09], [c.x, c.y + fw_ft(4), fw_ft(10)], [0, 0, 1], true) }],
  ['FW-03-顶视图',   -> { fw_cam([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false) }]
]
VIEWS2.each do |name, mk|
  begin
    view.camera = mk.call
    f = File.join(FW_EXP, "#{name}.png")
    ok = view.write_image(filename: f, width: 1920, height: 1080, antialias: true)
    puts "export #{f}: #{ok}"
  rescue => e
    puts "export error (#{name}): #{e.message}"
  end
end

begin
  model.save(FW_SKP)
  puts 'SAVED'
rescue => e
  puts "save: #{e.message}"
end
'FW-REEXPORT-DONE'
