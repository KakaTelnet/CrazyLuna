import { createServer } from 'node:http';
import { open, realpath, stat } from 'node:fs/promises';
import { constants } from 'node:fs';
import { basename, dirname, isAbsolute, join, resolve } from 'node:path';
import { createInterface } from 'node:readline';
import { fileURLToPath } from 'node:url';
import { parseDocument } from './parse.mjs';

const allowedFlags = new Set(['project', 'commander', 'execution', 'plan']);
const options = {};
for (let index = 2; index < process.argv.length; index += 2) {
  const flag = process.argv[index]?.replace(/^--/, '');
  const value = process.argv[index + 1];
  if (!allowedFlags.has(flag) || !value || !process.argv[index].startsWith('--')) {
    throw new Error('用法：node server.mjs --project /绝对项目路径 [--commander /记录.md] [--execution /记录.md] [--plan /方案.md]');
  }
  options[flag] = value;
}
if (!options.project) throw new Error('缺少 --project');
const project = await realpath(resolve(options.project));
if (!(await stat(project)).isDirectory()) throw new Error('目标项目不是目录');
const dashboard = dirname(fileURLToPath(import.meta.url));
const MAX_FILE_BYTES = 5 * 1024 * 1024;
const sourcePaths = {};

function recordPath(value) {
  if (value == null) return null;
  if (typeof value !== 'string' || !isAbsolute(value) || !value.endsWith('.md')) {
    throw new Error('记录路径必须是绝对路径且以 .md 结尾');
  }
  return value;
}

for (const key of ['commander', 'execution', 'plan']) sourcePaths[key] = recordPath(options[key]);

async function readContent(kind) {
  const path = sourcePaths[kind];
  if (!path) return null;
  const handle = await open(path, constants.O_RDONLY | constants.O_NOFOLLOW);
  try {
    const info = await handle.stat();
    if (!info.isFile() || info.size > MAX_FILE_BYTES) throw new Error('记录文件不是普通文件或超过 5 MB');
    return { content: await handle.readFile({ encoding: 'utf8' }), modifiedAt: info.mtime.toISOString() };
  } finally {
    await handle.close();
  }
}

async function readSource(kind) {
  if (!sourcePaths[kind]) return { configured: false };
  const name = basename(sourcePaths[kind]);
  try {
    const value = await readContent(kind);
    const parsed = parseDocument(value.content);
    return {
      configured: true,
      name,
      modifiedAt: value.modifiedAt,
      title: parsed.title,
      goalId: kind === 'commander' ? parsed.goalId : '',
      tasks: kind === 'execution' ? parsed.tasks : [],
    };
  } catch (error) {
    if (error.code === 'ENOENT') return { configured: true, name, pending: true };
    return { configured: true, name, error: '记录暂时无法读取' };
  }
}

function respond(response, status, type, body) {
  response.writeHead(status, {
    'Content-Type': type,
    'Cache-Control': 'no-store',
    'X-Content-Type-Options': 'nosniff',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': "default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; base-uri 'none'; frame-ancestors 'none'",
  });
  response.end(body);
}

function json(response, status, value) {
  respond(response, status, 'application/json; charset=utf-8', JSON.stringify(value));
}

const server = createServer(async (request, response) => {
  try {
    if (request.headers.host !== `127.0.0.1:${server.address().port}`) {
      return json(response, 403, { error: '只接受本地面板地址' });
    }
    if (request.method !== 'GET') return json(response, 405, { error: '只支持 GET' });
    const url = new URL(request.url, 'http://127.0.0.1');
    if (url.pathname === '/api/state') {
      const [commander, execution, plan] = await Promise.all(
        ['commander', 'execution', 'plan'].map(readSource),
      );
      return json(response, 200, { project, checkedAt: new Date().toISOString(), commander, execution, plan });
    }
    if (url.pathname === '/api/document') {
      const kind = url.searchParams.get('kind');
      if (!['commander', 'execution', 'plan'].includes(kind)) return json(response, 400, { error: '未知记录' });
      if (!sourcePaths[kind]) return json(response, 404, { error: '尚未指定记录' });
      try {
        const value = await readContent(kind);
        return respond(response, 200, 'text/plain; charset=utf-8', value.content);
      } catch {
        return json(response, 404, { error: '记录暂时无法读取' });
      }
    }
    const assets = new Map([
      ['/', ['index.html', 'text/html; charset=utf-8']],
      ['/app.js', ['app.js', 'text/javascript; charset=utf-8']],
      ['/style.css', ['style.css', 'text/css; charset=utf-8']],
    ]);
    const asset = assets.get(url.pathname);
    if (!asset) return json(response, 404, { error: '未找到页面' });
    const handle = await open(join(dashboard, asset[0]), constants.O_RDONLY | constants.O_NOFOLLOW);
    try {
      return respond(response, 200, asset[1], await handle.readFile());
    } finally {
      await handle.close();
    }
  } catch {
    return json(response, 500, { error: '读取失败，请查看服务终端' });
  }
});

createInterface({ input: process.stdin }).on('line', (line) => {
  try {
    const update = JSON.parse(line);
    if (!update || typeof update !== 'object' || Array.isArray(update) ||
        !Object.keys(update).every((key) => ['commander', 'execution', 'plan'].includes(key))) {
      throw new Error('无效的记录更新');
    }
    const paths = Object.fromEntries(Object.entries(update).map(([kind, value]) => [kind, recordPath(value)]));
    Object.assign(sourcePaths, paths);
    console.log('面板记录来源已更新');
  } catch {
    console.error('面板记录来源更新失败');
  }
});

server.listen(0, '127.0.0.1', () => {
  console.log(`Crazy Luna 只读面板：http://127.0.0.1:${server.address().port}`);
});
