# encoding: UTF-8
# ============================================================
# SketchUp MCP Bridge v1.1  (su_mcp_bridge.rb)
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

module SU_MCP
  PORT = 5768
  STATUS_FILE = 'C:/Users/muliz/.zcode/workspace/default/cad2skp/bridge_status.json'
  @@queue = Queue.new
  @@mutex = Mutex.new
  @@server = nil

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

  def self.start
    return if @@server
    begin
      @@server = TCPServer.new('127.0.0.1', PORT)
    rescue => e
      puts "SU_MCP: port #{PORT} failed: #{e.message}"
      return
    end
    Thread.new do
      loop do
        begin
          client = @@server.accept
        rescue
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
    UI.start_timer(0.1, true) do
      until @@queue.empty?
        job = @@queue.pop rescue break
        next unless claim(job)
        run_job(job)
      end
    end
    begin
      if File.directory?(File.dirname(STATUS_FILE))
        File.write(STATUS_FILE, JSON.generate(port: PORT, pid: Process.pid,
                                              version: '1.1', started: Time.now.to_s))
      end
    rescue
    end
    puts "SU_MCP v1.1: listening on 127.0.0.1:#{PORT}"
  end

  unless file_loaded?('su_mcp_bridge.rb')
    UI.menu('Plugins').add_item('MCP Bridge 重启服务') do
      @@server = nil
      start
    end
    file_loaded('su_mcp_bridge.rb')
  end
  start
end
