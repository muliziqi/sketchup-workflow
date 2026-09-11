#!/usr/bin/env node
// ============================================================
// 社区 SketchUp MCP stdio 适配器(零依赖)
// 复用 mhyrr/sketchup-mcp 的工具面与其 SketchUp 插件(TCP 9876
// 直连命令格式),补齐 get_scene_info(经 eval_ruby 组合)。
// 协议: MCP stdio(JSON-RPC 2.0, 按行) <-> TCP 9876(按行 JSON-RPC)
// ============================================================
import net from 'node:net';
import readline from 'node:readline';

const HOST = process.env.SU_MCP_HOST || '127.0.0.1';
const PORT = parseInt(process.env.SU_MCP_PORT || '9876', 10);

function callSketchup(req, timeoutMs = 90000) {
  return new Promise((resolve, reject) => {
    const sock = net.connect(PORT, HOST, () => {
      sock.write(JSON.stringify(req) + '\n');
    });
    let buf = '';
    const timer = setTimeout(() => {
      sock.destroy();
      reject(new Error(`SketchUp 社区桥(${HOST}:${PORT})响应超时——确认已 Start Server 且窗口未最小化`));
    }, timeoutMs);
    sock.on('data', (d) => {
      buf += d.toString('utf8');
      const idx = buf.indexOf('\n');
      if (idx >= 0) {
        clearTimeout(timer);
        sock.end();
        try { resolve(JSON.parse(buf.slice(0, idx))); }
        catch { reject(new Error('无法解析桥返回: ' + buf.slice(0, 200))); }
      }
    });
    sock.on('error', (e) => {
      clearTimeout(timer);
      reject(new Error(`无法连接 SketchUp 社区插件(${HOST}:${PORT}): ${e.message}。请确认 1) SketchUp 已打开 2) 扩展程序 > MCP Server > Start Server 已执行`));
    });
  });
}

async function callTool(name, args) {
  const res = await callSketchup({ command: name, parameters: args || {}, id: Date.now() });
  if (res.error) throw new Error(res.error.message || 'tool error');
  return res.result;
}

const TOOL_DEFS = [
  ['get_selection', '获取当前选中的图元信息', {}],
  ['create_component', '创建基本体组件(type: cube/cylinder/sphere/cone, 含位置与尺寸)', {
    type: 'object',
    properties: {
      type: { type: 'string', enum: ['cube', 'cylinder', 'sphere', 'cone'], description: '基本体类型' },
      position: { type: 'array', items: { type: 'number' }, description: '[x,y,z] 位置(英寸)' },
      width: { type: 'number' }, depth: { type: 'number' }, height: { type: 'number' }, radius: { type: 'number' },
    },
    required: ['type'],
  }],
  ['delete_component', '删除组件', { type: 'object', properties: { entity_id: { type: 'string' } } }],
  ['transform_component', '移动/旋转/缩放组件', {
    type: 'object',
    properties: {
      entity_id: { type: 'string' },
      translation: { type: 'array', items: { type: 'number' } },
      rotation: { type: 'number', description: '旋转角度(弧度)' },
      scale: { type: 'array', items: { type: 'number' } },
    },
  }],
  ['set_material', '给组件上材质(red/green/blue/yellow/cyan/magenta/white 等命名色)', {
    type: 'object',
    properties: { entity_id: { type: 'string' }, color: { type: 'string' } }, required: ['entity_id', 'color'],
  }],
  ['export_scene', '导出场景(skp/obj/dae/stl/png/jpg)', {
    type: 'object',
    properties: { format: { type: 'string', enum: ['skp', 'obj', 'dae', 'stl', 'png', 'jpg'] }, path: { type: 'string' } },
    required: ['format', 'path'],
  }],
  ['boolean_operation', '实体布尔运算', {
    type: 'object',
    properties: { operation: { type: 'string', enum: ['union', 'subtract', 'trim', 'intersect'] }, a: { type: 'string' }, b: { type: 'string' } },
    required: ['operation', 'a', 'b'],
  }],
  ['chamfer_edges', '边倒角', { type: 'object', properties: { entity_id: { type: 'string' }, distance: { type: 'number' } } }],
  ['fillet_edges', '边圆角', { type: 'object', properties: { entity_id: { type: 'string' }, radius: { type: 'number' } } }],
  ['create_mortise_tenon', '创建榫卯(Mortise & Tenon)构件', { type: 'object', properties: {} }],
  ['create_dovetail', '创建燕尾榫构件', { type: 'object', properties: {} }],
  ['create_finger_joint', '创建指接榫构件', { type: 'object', properties: {} }],
  ['eval_ruby', '在 SketchUp 内执行任意 Ruby 代码(终极手段, 可完成一切操作)', {
    type: 'object', properties: { code: { type: 'string' } }, required: ['code'],
  }],
];

async function getSceneInfo() {
  // 社区插件未内置 get_scene_info, 经 eval_ruby 组合实现
  const res = await callTool('eval_ruby', {
    code: [
      'm = Sketchup.active_model',
      'bb = m.bounds',
      "\"#{m.title} | entities=#{m.entities.length} | defs=#{m.definitions.count} | pages=#{m.pages.count} | \" +",
      '"bounds=" + bb.min.to_a.map { |v| v.round(1) }.to_s + ".." + bb.max.to_a.map { |v| v.round(1) }.to_s',
    ].join("\n"),
  });
  return res;
}

const TOOLS = TOOL_DEFS.map(([name, description, inputSchema]) => ({ name, description, inputSchema }));

async function dispatch(name, args) {
  switch (name) {
    case 'get_scene_info': return getSceneInfo();
    default: {
      const def = TOOL_DEFS.find((t) => t[0] === name);
      if (!def) throw new Error('unknown tool: ' + name);
      return callTool(name, args || {});
    }
  }
}

const rl = readline.createInterface({ input: process.stdin, terminal: false });
function send(obj) { process.stdout.write(JSON.stringify(obj) + '\n'); }

rl.on('line', async (line) => {
  line = line.trim();
  if (!line) return;
  let msg;
  try { msg = JSON.parse(line); } catch { return; }
  if (msg.id === undefined || msg.id === null) return;
  const { id, method, params } = msg;
  try {
    if (method === 'initialize') {
      send({
        jsonrpc: '2.0', id,
        result: {
          protocolVersion: msg.params?.protocolVersion || '2024-11-05',
          capabilities: { tools: {} },
          serverInfo: { name: 'sketchup-community-mcp', version: '1.0.0' },
        },
      });
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
process.stderr.write(`sketchup-community-mcp ready (target ${HOST}:${PORT})\n`);
