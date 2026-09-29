const $ = (id) => document.getElementById(id);
const statusNames = { TODO: '待办', RUNNING: '进行中', VERIFYING: '验收中', PASS: '已通过', PARTIAL: '部分完成', REWORK: '返工中', BLOCKED: '受阻', UNKNOWN: '待核实' };
let refreshVersion = 0;

function displayTime(value) {
  if (!value) return '—';
  return new Intl.DateTimeFormat('zh-CN', { dateStyle: 'short', timeStyle: 'medium' }).format(new Date(value));
}

function textElement(tag, className, value) {
  const element = document.createElement(tag);
  if (className) element.className = className;
  element.textContent = value;
  return element;
}

function setLink(element, kind, available) {
  element.classList.toggle('hidden', !available);
  if (available) element.href = `/api/document?kind=${kind}`;
  else element.removeAttribute('href');
}

function sourceLabel(record) {
  if (!record?.configured) return '尚未指定';
  if (record.pending) return `${record.name} · 等待生成`;
  if (record.error) return `${record.name} · 无法读取`;
  return `${record.name} · ${displayTime(record.modifiedAt)}`;
}

function renderRole(kind, record) {
  const fallback = record?.pending ? '记录尚未生成' : record?.error ? '记录暂时无法读取' : '等待记录路径';
  $(`${kind}Title`).textContent = record?.title ?? fallback;
  $(`${kind}Source`).textContent = sourceLabel(record);
  setLink($(`${kind}Link`), kind, Boolean(record?.title));
}

function renderStats(tasks) {
  const stats = $('stats');
  stats.replaceChildren();
  for (const [status, label] of Object.entries(statusNames)) {
    const count = tasks.filter((task) => task.status === status).length;
    const item = textElement('div', `stat stat-${status.toLowerCase()}`, '');
    item.append(textElement('strong', '', String(count)), textElement('span', '', label));
    stats.append(item);
  }
}

function renderTasks(record) {
  const tasks = record?.tasks ?? [];
  $('taskCount').textContent = String(tasks.length);
  renderStats(tasks);
  const list = $('taskList');
  list.replaceChildren();
  if (!record?.title) {
    const message = record?.error ? '执行记录暂时无法读取，请在 Commander 中核对路径与权限。'
      : '执行记录生成后，这里会显示可识别的任务表。';
    list.append(textElement('p', 'empty', message));
    return;
  }
  if (!tasks.length) {
    list.append(textElement('p', 'empty', '未识别到带“任务”和“状态”列的任务表。请查看原文核对记录格式。'));
    return;
  }
  for (const task of tasks) {
    const card = textElement('article', 'task-card', '');
    const header = textElement('div', 'task-header', '');
    const heading = textElement('div', 'task-heading', '');
    heading.append(textElement('span', 'task-id', task.id), textElement('h3', '', task.subject || '未写任务名称'));
    header.append(heading, textElement('span', `badge badge-${task.status.toLowerCase()}`, statusNames[task.status] ?? task.status));
    card.append(header);
    const details = textElement('div', 'task-details', '');
    details.append(textElement('span', '', task.section));
    if (task.acceptance) details.append(textElement('span', '', `验收：${task.acceptance}`));
    if (task.owner) details.append(textElement('span', '', `负责人：${task.owner}`));
    if (task.rawStatus && task.rawStatus !== task.status) details.append(textElement('span', '', `原状态：${task.rawStatus}`));
    card.append(details);
    if (task.blocker) card.append(textElement('p', 'blocker', `阻塞：${task.blocker}`));
    card.append(textElement('p', 'evidence', task.evidence || '记录表中未写证据入口'));
    const source = textElement('a', 'record-link', `执行记录第 ${task.line} 行 ↗`);
    source.href = '/api/document?kind=execution';
    source.target = '_blank';
    source.rel = 'noopener';
    card.append(source);
    list.append(card);
  }
}

async function refresh() {
  const version = ++refreshVersion;
  try {
    const response = await fetch('/api/state');
    const data = await response.json();
    if (version !== refreshVersion) return;
    if (!response.ok) throw new Error(data.error ?? '读取记录失败');
    $('projectName').textContent = data.project.split('/').filter(Boolean).at(-1) ?? data.project;
    $('projectPath').textContent = data.project;
    $('checkedAt').textContent = displayTime(data.checkedAt);
    $('goalId').textContent = data.commander?.goalId ? `目标标识：${data.commander.goalId}` : '目标标识待记录';
    for (const kind of ['commander', 'execution', 'plan']) renderRole(kind, data[kind]);
    const loaded = ['commander', 'execution', 'plan'].filter((kind) => data[kind]?.title).length;
    $('sourceHint').textContent = `${loaded} / 3 份记录可读取 · 自动刷新中`;
    renderTasks(data.execution);
    $('error').classList.add('hidden');
  } catch (error) {
    $('error').textContent = error.message;
    $('error').classList.remove('hidden');
  }
}

$('refresh').addEventListener('click', refresh);
refresh();
setInterval(refresh, 10_000);
