const TASK_ID = /\bT\d{2,}\b/i;
const STATUS = /\b(TODO|RUNNING|VERIFYING|PASS|REWORK|BLOCKED|PARTIAL)\b/i;

function cells(line) {
  const value = line.trim();
  if (!value.startsWith('|') || !value.endsWith('|')) return null;
  return value.slice(1, -1).split(/(?<!\\)\|/).map((cell) => cell.trim().replace(/\\\|/g, '|'));
}

function plain(value = '') {
  return value
    .replace(/`([^`]*)`/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]*\)/g, '$1')
    .replace(/\*\*|__/g, '')
    .trim();
}

function column(headers, names) {
  return headers.findIndex((header) => names.some((name) => header.includes(name)));
}

export function parseDocument(content) {
  const lines = content.split(/\r?\n/);
  const title = plain(lines.find((line) => /^#\s+/.test(line))?.replace(/^#\s+/, '') ?? '未命名记录');
  const goalId = plain(content.match(/目标标识[：:]\s*([^。\n]+)/)?.[1] ?? '').split(/[，,；;]/)[0];
  const tasks = new Map();
  let section = title;

  for (let i = 0; i < lines.length; i += 1) {
    const heading = lines[i].match(/^#{1,6}\s+(.+)/);
    if (heading) section = plain(heading[1]);

    const headers = cells(lines[i]);
    const separator = cells(lines[i + 1] ?? '');
    if (!headers || !separator || separator.length !== headers.length ||
        !separator.every((item) => /^:?-{3,}:?$/.test(item))) continue;

    const taskColumn = column(headers, ['任务']);
    const statusColumn = column(headers, ['状态']);
    if (taskColumn < 0 || statusColumn < 0) continue;
    const evidenceColumn = column(headers, ['证据', '产物']);
    const acceptanceColumn = column(headers, ['验收', 'AC']);
    const ownerColumn = column(headers, ['负责人', '角色', '责任', '写入者']);
    const blockerColumn = column(headers, ['阻塞', '待解决']);

    for (let j = i + 2; j < lines.length; j += 1) {
      const row = cells(lines[j]);
      if (!row || row.length !== headers.length) break;
      const id = plain(row[taskColumn]).match(TASK_ID)?.[0]?.toUpperCase();
      if (!id) continue;
      const rawStatus = plain(row[statusColumn]);
      let status = rawStatus.match(STATUS)?.[1]?.toUpperCase() ?? 'UNKNOWN';
      if (status === 'PASS' && /限制|除外|部分|except|partial/i.test(rawStatus)) status = 'PARTIAL';
      const taskName = plain(row[taskColumn]).replace(TASK_ID, '').trim();
      const subject = taskName || plain(row[0]);
      tasks.set(id, {
        id,
        subject: subject === id ? '' : subject,
        status,
        rawStatus,
        section,
        acceptance: acceptanceColumn < 0 ? '' : plain(row[acceptanceColumn]),
        evidence: evidenceColumn < 0 ? '' : plain(row[evidenceColumn]),
        owner: ownerColumn < 0 ? '' : plain(row[ownerColumn]),
        blocker: blockerColumn < 0 ? '' : plain(row[blockerColumn]),
        line: j + 1,
      });
    }
  }

  return { title, goalId, tasks: [...tasks.values()] };
}
