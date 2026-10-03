# encoding: UTF-8
# 流水别墅模型精修: 树木落地 + 相机拉近重出图
# 前提: examples/fallingwater.rb 已建成的模型处于打开状态(本脚本不重建模型,
# 不去加载 fallingwater.rb —— 那会触发其 clear! 全量重建)
# 路径三级回退: __dir__(仓库根) -> ENV['SKWF_HOME'] -> ~/sketchup-workflow
# 常量在 $VERBOSE=nil 下赋值, 重复 load 抑制 already initialized constant 警告
_old_verbose = $VERBOSE
$VERBOSE = nil
begin
  FT = 12.0
  SKWF_ROOT =
    if __dir__
      File.expand_path('..', __dir__)
    elsif ENV['SKWF_HOME'] && !ENV['SKWF_HOME'].empty?
      File.expand_path(ENV['SKWF_HOME'])
    else
      File.join(Dir.home, 'sketchup-workflow')
    end
  FW_EXP = File.join(SKWF_ROOT, 'exports')
  FW_SKP = File.join(SKWF_ROOT, 'Fallingwater_v01.skp')
  FW_Z = Geom::Vector3d.new(0, 0, 1)
ensure
  $VERBOSE = _old_verbose
end

# 尺寸换算(与 examples/fallingwater.rb:56 的 fw_ft 同口径; 本文件独立可用,
# 不依赖先加载 fallingwater.rb)
def fw_ft(v)
  v * 12.0
end

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
