# encoding: UTF-8
# 拉塔皮 v2: 相机拉远重出图
FT = 12.0
LAT2_EXP = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/exports'
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
