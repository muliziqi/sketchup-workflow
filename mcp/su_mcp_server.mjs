#!/usr/bin/env node
// ============================================================
// SketchUp MCP stdio 服务器 (零依赖, Node >= 18)
// 依赖: SketchUp 内运行 su_mcp_bridge.rb 插件 (TCP 127.0.0.1:5768)
//
// ZCode / Claude Desktop / Cursor 等 MCP 客户端配置示例:
//   command: node
//   args:    ["/path/to/su_mcp_server.mjs"]
// 环境变量: SU_MCP_HOST(默认 127.0.0.1), SU_MCP_PORT(默认 5768)
// ============================================================
import net from 'node:net';
import readline from 'node:readline';

const HOST = process.env.SU_MCP_HOST || '127.0.0.1';
const PORT = parseInt(process.env.SU_MCP_PORT || '5768', 10);

function callBridge(req, timeoutMs = 90000) {
  return new Promise((resolve, reject) => {
    let sock;
    try {
      sock = net.connect(PORT, HOST, () => {
        sock.write(JSON.stringify(req) + '\n');
      });
    } catch (e) {
      reject(new Error(`无法连接 SketchUp 桥(${HOST}:${PORT}): ${e.message}`));
      return;
    }
    let buf = '';
    const timer = setTimeout(() => {
      sock.destroy();
      reject(new Error('SketchUp 桥响应超时(模型是否正忙?)'));
    }, timeoutMs);
    sock.on('data', (d) => {
      buf += d.toString('utf8');
      const idx = buf.indexOf('\n');
      if (idx >= 0) {
        clearTimeout(timer);
        sock.end();
        try {
          resolve(JSON.parse(buf.slice(0, idx)));
        } catch {
          reject(new Error('桥返回了无法解析的数据: ' + buf.slice(0, 200)));
        }
      }
    });
    sock.on('error', (e) => {
      clearTimeout(timer);
      reject(new Error(
        `无法连接 SketchUp 桥(${HOST}:${PORT}): ${e.message}。` +
        '请确认: 1) SketchUp 已打开  2) 已安装 su_mcp_bridge.rb 插件  3) 端口未被占用'));
    });
  });
}

const TOOLS = [
  { name: 'su_ping', description: '检测 SketchUp 桥是否在线, 返回 SketchUp 版本与当前模型文件名', inputSchema: { type: 'object', properties: {} } },
  { name: 'su_model_info', description: '获取当前模型信息: 路径、实体数、组件定义数、场景数、材质数、包围盒范围', inputSchema: { type: 'object', properties: {} } },
  { name: 'su_tags', description: '获取当前模型的标记(Tag/图层)列表', inputSchema: { type: 'object', properties: {} } },
  { name: 'su_pages', description: '获取当前模型的场景列表', inputSchema: { type: 'object', properties: {} } },
  {
    name: 'su_eval_ruby',
    description: '在 SketchUp 内以 UI 主线程执行任意 Ruby 代码。变量 model = Sketchup.active_model 可直接使用。可完成建墙、上材质、建场景等一切操作。执行有风险的操作前建议先 su_save。',
    inputSchema: { type: 'object', properties: { code: { type: 'string', description: 'Ruby 代码, 可多行' } }, required: ['code'] },
  },
  { name: 'su_save', description: '保存当前模型', inputSchema: { type: 'object', properties: { path: { type: 'string', description: '保存路径(.skp), 缺省为当前路径' } } } },
  { name: 'su_export_png', description: '把当前视图导出为 PNG 图片', inputSchema: { type: 'object', properties: { path: { type: 'string' }, width: { type: 'number' }, height: { type: 'number' } }, required: ['path'] } },
  { name: 'su_zoom_extents', description: '视图全屏缩放(显示全部模型)', inputSchema: { type: 'object', properties: {} } },
];

async function dispatch(name, args) {
  switch (name) {
    case 'su_ping': return callBridge({ cmd: 'ping' });
    case 'su_model_info': return callBridge({ cmd: 'model_info' });
    case 'su_tags': return callBridge({ cmd: 'tags' });
    case 'su_pages': return callBridge({ cmd: 'pages' });
    case 'su_eval_ruby': return callBridge({ cmd: 'eval', code: args.code || '' });
    case 'su_save': return callBridge({ cmd: 'save', path: args.path || '' });
    case 'su_export_png': return callBridge({ cmd: 'export_png', path: args.path, width: args.width, height: args.height });
    case 'su_zoom_extents': return callBridge({ cmd: 'zoom_extents' });
    default: throw new Error('unknown tool: ' + name);
  }
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
function send(obj) {
  process.stdout.write(JSON.stringify(obj) + '\n');
}

rl.on('line', async (line) => {
  line = line.trim();
  if (!line) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  if (msg.id === undefined || msg.id === null) return; // 通知类消息不回复
  const { id, method, params } = msg;
  try {
    if (method === 'initialize') {
      send({
        jsonrpc: '2.0', id,
        result: {
          protocolVersion: msg.params?.protocolVersion || '2024-11-05',
          capabilities: { tools: {} },
          serverInfo: { name: 'sketchup-bridge', version: '1.0.0' },
        },
      });
    } else if (method === 'notifications/initialized') {
      // 无需回复
    } else if (method === 'tools/list') {
      send({ jsonrpc: '2.0', id, result: { tools: TOOLS } });
    } else if (method === 'tools/call') {
      const { name, arguments: args } = params || {};
      try {
        const res = await dispatch(name, args || {});
        send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: JSON.stringify(res, null, 2) }] } });
      } catch (e) {
        send({ jsonrpc: '2.0', id, result: { content: [{ type: 'text', text: 'ERROR: ' + e.message }], isError: true } });
      }
    } else if (method === 'ping') {
      send({ jsonrpc: '2.0', id, result: {} });
    } else {
      send({ jsonrpc: '2.0', id, error: { code: -32601, message: 'method not found: ' + method } });
    }
  } catch (e) {
    send({ jsonrpc: '2.0', id, error: { code: -32700, message: e.message } });
  }
});

process.on('SIGINT', () => process.exit(0));
process.stderr.write(`sketchup-bridge MCP server ready (target ${HOST}:${PORT})\n`);
