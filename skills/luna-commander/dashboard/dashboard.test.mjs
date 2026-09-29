import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { mkdtemp, mkdir, readFile, rm, symlink, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { dirname, join } from 'node:path';
import { test } from 'node:test';
import { fileURLToPath } from 'node:url';
import { parseDocument } from './parse.mjs';

test('读取任务表并采用同一任务最后一次状态', () => {
  const result = parseDocument(`# 执行记录
| 需求 | 任务 | 验收 | 当前状态 | 原始证据入口 |
| --- | --- | --- | --- | --- |
| 清理标签 | T01 | AC01 | RUNNING | 初次执行 |
## R02
| 需求 | 任务 | 验收 | 当前状态 | 原始证据入口 |
| --- | --- | --- | --- | --- |
| 清理标签 | T01 | AC01 | PASS | 独立验收通过 |
| 空白标签 | T02 | AC02 | BLOCKED | 等待输入 |
| 控制消息 | R02-1 | 无 | 完成 | 不属于任务 |
`);
  assert.equal(result.title, '执行记录');
  assert.deepEqual(result.tasks.map(({ id, status, section }) => [id, status, section]), [
    ['T01', 'PASS', 'R02'], ['T02', 'BLOCKED', 'R02'],
  ]);
  assert.equal(result.tasks[0].evidence, '独立验收通过');
});

test('限定通过与未知状态不会误显示为已通过', () => {
  const result = parseDocument(`# 执行记录
| 任务 | 状态 | 唯一写入者 / 责任 | 原始证据 |
| --- | --- | --- | --- |
| T03 诊断 | PARTIAL | 诊断 Agent | 还需验证 |
| T04 验收 | PASS（AC05 限制除外） | 验收 Agent | 存在缺口 |
| T05 后续 | 等待条件 | 协调者 | 未开始 |
`);
  assert.deepEqual(result.tasks.map(({ status }) => status), ['PARTIAL', 'PARTIAL', 'UNKNOWN']);
  assert.equal(result.tasks[1].rawStatus, 'PASS（AC05 限制除外）');
  assert.equal(result.tasks[2].owner, '协调者');
});

test('右侧面板读取指定的跨工作区记录并等待执行记录生成', async (context) => {
  const directory = await mkdtemp(join(tmpdir(), 'crazy-luna-dashboard-'));
  const commander = join(directory, 'ai_docs', 'logs', 'Commander.md');
  const plan = join(directory, 'ai_docs', 'notes', '方案.md');
  const execution = join(directory, 'worktree', 'ai_docs', 'logs', '执行.md');
  const linked = join(directory, 'ai_docs', 'logs', 'link.md');
  await mkdir(dirname(commander), { recursive: true });
  await mkdir(dirname(plan), { recursive: true });
  await mkdir(dirname(execution), { recursive: true });
  await writeFile(commander, '# Commander 记录\n目标标识：`demo-01`。\n');
  await writeFile(plan, '# 示例方案\n');
  await symlink(commander, linked);
  const child = spawn(process.execPath, [
    join(dirname(fileURLToPath(import.meta.url)), 'server.mjs'),
    '--project', directory, '--commander', commander, '--execution', execution, '--plan', plan,
  ], { stdio: ['pipe', 'pipe', 'pipe'] });
  context.after(async () => {
    child.kill();
    await rm(directory, { recursive: true, force: true });
  });
  let output = '';
  const base = await new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('面板服务启动超时')), 5000);
    child.stdout.on('data', (chunk) => {
      output += chunk;
      const match = output.match(/http:\/\/127\.0\.0\.1:\d+/);
      if (match) {
        clearTimeout(timeout);
        resolve(match[0]);
      }
    });
    child.once('exit', (code) => reject(new Error(`面板服务提前退出：${code}`)));
  });
  const first = await (await fetch(`${base}/api/state`)).json();
  assert.equal(first.commander.goalId, 'demo-01');
  assert.equal(first.plan.title, '示例方案');
  assert.equal(first.execution.pending, true);
  await writeFile(execution, '# 执行记录\n| 任务 | 状态 | 证据 |\n| --- | --- | --- |\n| T01 | PASS | 已验收 |\n');
  const current = await (await fetch(`${base}/api/state`)).json();
  assert.equal(current.execution.tasks[0].status, 'PASS');
  assert.equal(await (await fetch(`${base}/api/document?kind=execution`)).text(), await readFile(execution, 'utf8'));
  const updated = new Promise((resolve, reject) => {
    const timeout = setTimeout(() => reject(new Error('更新记录路径超时')), 5000);
    child.stdout.once('data', (chunk) => {
      clearTimeout(timeout);
      resolve(String(chunk));
    });
  });
  child.stdin.write(`${JSON.stringify({ execution: linked })}\n`);
  assert.match(await updated, /记录来源已更新/);
  assert.equal((await (await fetch(`${base}/api/state`)).json()).execution.error, '记录暂时无法读取');
  assert.equal((await fetch(`${base}/api/document?kind=execution`)).status, 404);
  assert.equal((await fetch(`${base}/api/document?kind=../outside`)).status, 400);
  assert.equal((await fetch(`${base}/api/state`, { method: 'POST' })).status, 405);
  assert.equal((await fetch(`${base}/`)).status, 200);
});
