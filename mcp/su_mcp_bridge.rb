# encoding: UTF-8
# ============================================================
# SketchUp MCP Bridge v1.3  (su_mcp_bridge.rb)
# 在 SketchUp 内启动本地 TCP JSON 服务, 供 MCP 服务器 / AI 客户端驱动。
# 协议: 每行一个 JSON 请求 {"id":1,"cmd":"ping"} -> 每行一个 JSON 响应
#
# 命令:
#   ping                          心跳
#   model_info                    模型概况(路径/实体数/范围/场景/材质)
#   tags                          标记列表
#   pages                         场景列表
#   eval       {code: "..."}      执行 Ruby(变量 model 可用)
#   save       {path: "..."}      保存模型(缺省存当前路径)
#   export_png {path, width, height}  导出当前视图 PNG
#   snapshot    {path?, width?, height?, camera?}  即时预览当前视图 PNG(可带相机 eye/target/up/persp)
#   look_around {dir?}            环绕 4 角 + 顶视, 一次输出 5 张检查快照到 exports/
#   zoom_extents                  全屏缩放
#
# 端口: 127.0.0.1:5768   仅本机回环, 无外部暴露
#
# 执行策略(双通道):
#   API 调用优先派给 UI 主线程(UI.start_timer); 若 SketchUp 失去焦点/
#   最小化导致定时器停摆, 2 秒后自动降级到工作线程执行(线程池串行化),
#   保证在后台也能响应。风险提示: 非 UI 线程调 API 非官方推荐,
#   社区同类项目(mhyrr/sketchup-mcp 等)即此方案。
# ============================================================
require 'socket'
require 'json'
require 'fileutils'

module SU_MCP_BRIDGE
  PORT = 5768
  # 缺省工作目录: SKWF_HOME -> 用户目录(Ruby 无 File.mkdir_p, 建多层目录用 FileUtils)
  SKWF_DIR =
    if ENV['SKWF_HOME'] && !ENV['SKWF_HOME'].empty?
      File.expand_path(ENV['SKWF_HOME'])
    else
      File.join(Dir.home, 'sketchup-workflow')
    end
  STATUS_FILE = File.join(SKWF_DIR, 'bridge_status.json')
  @@queue = Queue.new
  @@mutex = Mutex.new
  @@server = nil
  @@timer = nil
  @@accept_thread = nil

  def self.handle(req)
    cmd = req['cmd'].to_s
    model = Sketchup.active_model
    case cmd
    when 'ping'
      { ok: true, reply: 'pong', sketchup_version: Sketchup.version.to_s,
        model: File.basename(model.path.to_s) }
    when 'model_info'
      bb = model.bounds
      { ok: true, path: model.path, entities: model.entities.length,
        definitions: model.definitions.count, pages: model.pages.count,
        materials: model.materials.count,
        bounds_min: bb.min.to_a.map { |v| v.round(2) },
        bounds_max: bb.max.to_a.map { |v| v.round(2) } }
    when 'tags'
      { ok: true, tags: model.layers.to_a.map(&:name) }
    when 'pages'
      { ok: true, pages: model.pages.to_a.map(&:name) }
    when 'eval'
      code = req['code'].to_s
      b = binding
      b.local_variable_set(:model, model)
      val = eval(code, b, 'su_mcp_eval', 1)
      { ok: true, result: val.inspect }
    when 'save'
      path = req['path'].to_s
      if path.empty?
        model.save
      else
        model.save(path)
      end
      { ok: true, path: model.path }
    when 'export_png'
      v = model.active_view
      ok = v.write_image(filename: req['path'].to_s,
                         width: (req['width'] || 1920),
                         height: (req['height'] || 1080),
                         antialias: true)
      { ok: ok, path: req['path'].to_s }
    when 'zoom_extents'
      model.active_view.zoom_extents
      { ok: true }
    when 'snapshot'
      # 即时预览: 可带 camera {eye,target,up,persp}, 缺省输出 preview.png
      if req['path'].to_s.empty?
        FileUtils.mkdir_p(SKWF_DIR)
        path = File.join(SKWF_DIR, 'preview.png')
      else
        path = req['path'].to_s
      end
      w = req['width'] || 1280
      h = req['height'] || 720
      v = model.active_view
      cam = req['camera']
      if cam.is_a?(Hash)
        persp = cam.fetch('persp', true)
        begin
          v.camera = Sketchup::Camera.new(cam['eye'], cam['target'], cam['up'] || [0, 0, 1], persp)
        rescue
          v.camera = Sketchup::Camera.new(cam['eye'], cam['target'], cam['up'] || [0, 0, 1])
        end
      end
      ok = v.write_image(filename: path, width: w, height: h, antialias: true)
      { ok: ok, path: path }
    when 'look_around'
      # AI 视觉检查: 环绕 4 角 + 顶视, 一次输出 5 张快照
      bb = model.bounds
      c = bb.center
      diag = bb.diagonal
      base = req['dir'] || File.join(SKWF_DIR, 'exports')
      FileUtils.mkdir_p(base) unless File.directory?(base)
      tz = bb.min.z + (bb.max.z - bb.min.z) * 0.3
      shots = []
      angles = [['SE', diag * 0.35, -diag * 0.35], ['SW', -diag * 0.35, -diag * 0.35],
                ['NW', -diag * 0.35, diag * 0.35], ['NE', diag * 0.35, diag * 0.35]]
      angles.each_with_index do |(nm, dx, dy), i|
        begin
          v.camera = Sketchup::Camera.new([c.x + dx, c.y + dy, bb.max.z + diag * 0.15],
                                          [c.x, c.y, tz], [0, 0, 1], true)
        rescue
          v.camera = Sketchup::Camera.new([c.x + dx, c.y + dy, bb.max.z + diag * 0.15],
                                          [c.x, c.y, 0], [0, 0, 1])
        end
        p = File.join(base, "preview_#{i + 1}_#{nm}.png")
        ok = false
        begin
          ok = v.write_image(filename: p, width: 1024, height: 640, antialias: true)
        rescue
        end
        shots << { name: nm, path: p, ok: ok }
      end
      begin
        v.camera = Sketchup::Camera.new([c.x, c.y - 1, bb.max.z + diag], [c.x, c.y, 0], [0, 1, 0], false)
      rescue
      end
      p = File.join(base, 'preview_5_TOP.png')
      ok = false
      begin
        ok = v.write_image(filename: p, width: 1024, height: 640, antialias: true)
      rescue
      end
      shots << { name: 'TOP', path: p, ok: ok }
      { ok: true, shots: shots }
    else
      { ok: false, error: "unknown cmd: #{cmd}" }
    end
  rescue Exception => e
    { ok: false, error: "#{e.class}: #{e.message}" }
  end

  def self.run_job(job)
    begin
      job[:resp] = handle(job[:req])
    rescue => e
      job[:resp] = { ok: false, error: "#{e.class}: #{e.message}" }
    end
    job[:done] = true
  end

  def self.claim(job)
    got = false
    @@mutex.synchronize do
      unless job[:claimed]
        job[:claimed] = true
        got = true
      end
    end
    got
  end

  # 重启/热重载前: 关闭旧 accept 线程与旧 TCPServer。
  # 不关的话旧线程仍在 accept, 旧 socket 仍占着端口, 新 TCPServer 会 EADDRINUSE
  def self.stop
    begin
      UI.stop_timer(@@timer) if @@timer
    rescue
    end
    @@timer = nil
    if @@accept_thread
      @@accept_thread.kill rescue nil
      @@accept_thread = nil
    end
    if @@server
      begin
        @@server.close rescue nil
      rescue
      end
      @@server = nil
    end
  end

  def self.start
    stop
    server_ok = false
    begin
      @@server = TCPServer.new('127.0.0.1', PORT)
      server_ok = true
    rescue => e
      puts "SU_MCP: port #{PORT} failed: #{e.message}"
      @@server = nil
    end
    if server_ok
      @@accept_thread = Thread.new do
        loop do
          begin
            client = @@server.accept
          rescue => e
            # 服务已停(重启)就退出线程; 否则继续 accept
            break if @@server.nil? || @@server.closed?
            next
          end
          Thread.new(client) do |c|
            begin
              while (line = c.gets)
                line = line.strip
                next if line.empty?
                begin
                  req = JSON.parse(line)
                rescue
                  c.puts(JSON.generate(ok: false, error: 'bad json'))
                  next
                end
                job = { req: req, done: false, claimed: false,
                        resp: nil, ts: Time.now }
                @@queue << job
                deadline = Time.now + 180
                while !job[:done] && Time.now < deadline
                  # UI 线程 2 秒没接活 -> 工作线程降级执行
                  if !job[:claimed] && Time.now > job[:ts] + 2.0 && claim(job)
                    run_job(job)
                  end
                  break if job[:done]
                  sleep 0.05
                end
                c.puts(JSON.generate(job[:resp] || { ok: false, error: 'timeout' }))
              end
            rescue
            ensure
              begin
                c.close
              rescue
              end
            end
          end
        end
      end
    end
    # 每次调用 start(含热重载)都强制重建 UI 定时器:
    # SketchUp 最小化会取消定时器, 不重建则队列永远无人处理
    begin
      UI.stop_timer(@@timer) if @@timer
    rescue
    end
    @@timer = UI.start_timer(0.1, true) do
      until @@queue.empty?
        job = @@queue.pop rescue break
        next unless claim(job)
        run_job(job)
      end
    end
    begin
      FileUtils.mkdir_p(File.dirname(STATUS_FILE))
      # ok 字段如实反映端口绑定结果: 绑定失败时状态文件不得误报在线
      File.write(STATUS_FILE, JSON.generate(port: PORT, pid: Process.pid,
                                            version: '1.3', ok: server_ok,
                                            started: Time.now.to_s))
    rescue
    end
    puts "SU_MCP v1.3: listening on 127.0.0.1:#{PORT}" if server_ok
  end

  unless file_loaded?('su_mcp_bridge.rb')
    UI.menu('Plugins').add_item('MCP Bridge 重启服务') do
      start   # start 内部先 stop: 关旧 accept 线程与 TCPServer 再重建
    end
    file_loaded('su_mcp_bridge.rb')
  end
  start
end
