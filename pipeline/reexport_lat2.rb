# encoding: UTF-8
# 拉塔皮 v2: 相机拉远重出图
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
  LAT2_EXP = File.join(SKWF_ROOT, 'exports')
ensure
  $VERBOSE = _old_verbose
end
model = Sketchup.active_model
def ft(v)
  v * 12.0
end
bb = model.bounds
c = bb.center
diag = bb.diagonal

def cam2(eye, target, up, persp)
  begin
    return Sketchup::Camera.new(eye, target, up, persp)
  rescue
  end
  Sketchup::Camera.new(eye, target, up)
end

view = model.active_view
# 关闭阴影: 透明膜屋面在 SketchUp 中仍会投影, 会导致阳光房内部全黑
begin
  model.shadow_info['ShadowsOn'] = false
rescue
end
VIEWS4 = [
  ['LT2-01-花园透视', -> { cam2([c.x + diag*0.55, c.y + diag*0.62, diag*0.22], [c.x, c.y, ft(3)], [0, 0, 1], true) }],
  ['LT2-02-街道透视', -> { cam2([c.x + diag*0.10, c.y - diag*0.62, diag*0.18], [c.x, c.y, ft(2.8)], [0, 0, 1], true) }],
  ['LT2-03-侧透视',   -> { cam2([c.x - diag*0.66, c.y + diag*0.04, diag*0.18], [c.x, c.y, ft(3)], [0, 0, 1], true) }],
  ['LT2-04-顶视图',   -> { cam2([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false) }]
]
VIEWS4.each do |name, mk|
  begin
    view.camera = mk.call
    f = File.join(LAT2_EXP, "#{name}.png")
    ok = view.write_image(filename: f, width: 1920, height: 1080, antialias: true)
    puts "export #{f}: #{ok}"
  rescue => e
    puts "export error (#{name}): #{e.message}"
  end
end
'LAT2-REEXPORT-DONE'
