import type { ExtensionAPI } from '@earendil-works/pi-coding-agent';
import { truncateToWidth, visibleWidth } from '@earendil-works/pi-tui';

const pad = (n: number) => String(n).padStart(2, '0');
const tokens = (n: number) => n < 1000 ? String(n) : `${Math.round(n / 1000)}k`;

function weekly(used: number, epoch: number) {
  const reset = new Date(epoch * 1000);
  const time = reset.getTime() > 0 ? `${pad(reset.getMonth() + 1)}/${pad(reset.getDate())} ${pad(reset.getHours())}:${pad(reset.getMinutes())}` : '—';
  return `${Number.isFinite(used) ? Math.round(used) + '%' : '—'} (reset ${time})`;
}

export default function (pi: ExtensionAPI) {
  const quotas = new Map<string, string>();
  let redraw = () => {};
  pi.on('after_provider_response', (event, ctx) => {
    const h = event.headers;
    const slot = ['primary', 'secondary'].find(s => Number(h[`x-codex-${s}-window-minutes`]) === 10080);
    const prefix = slot ? `x-codex-${slot}` : 'anthropic-ratelimit-unified-7d';
    const used = Number(h[`${prefix}-${slot ? 'used-percent' : 'utilization'}`]) * (slot ? 1 : 100);
    const reset = Number(h[`${prefix}-${slot ? 'reset-at' : 'reset'}`]);
    if (ctx.model && (Number.isFinite(used) || reset > 0)) {
      quotas.set(ctx.model.provider, weekly(used, reset)); redraw();
    }
  });
  pi.on('session_start', (_event, ctx) => {
    if (ctx.mode !== 'tui') return;
    ctx.ui.setWidget('extended-statusline', tui => {
      let diff = '—', busy = false, active = true, nextUsage = 0;
      const refreshUsage = async () => {
        const m = ctx.model;
        if (m?.provider !== 'openai-codex' || new URL(m.baseUrl).origin !== 'https://chatgpt.com' || Date.now() < nextUsage) return;
        nextUsage = Date.now() + 300000;
        try {
          const token = await ctx.modelRegistry.getApiKeyForProvider(m.provider);
          if (!token || !ctx.modelRegistry.isUsingOAuth(m)) return;
          const claims = JSON.parse(Buffer.from(token.split('.')[1], 'base64url').toString());
          const account = claims['https://api.openai.com/auth']?.chatgpt_account_id;
          const headers = { Authorization: `Bearer ${token}`, ...(account ? { 'ChatGPT-Account-Id': account } : {}) };
          const res = await fetch('https://chatgpt.com/backend-api/wham/usage', { headers, redirect: 'error', signal: AbortSignal.timeout(6000) });
          if (!res.ok) return;
          const { rate_limit } = await res.json();
          const w = [rate_limit?.primary_window, rate_limit?.secondary_window].find(x => x?.limit_window_seconds === 604800);
          if (active && w) { quotas.set(m.provider, weekly(w.used_percent, w.reset_at)); tui.requestRender(); }
        } catch { /* No usage service: keep the last provider-reported value. */ }
      };
      const refresh = async () => {
        if (busy || !active) return;
        busy = true;
        const git = (...args: string[]) => pi.exec('git', ['--no-optional-locks', ...args], { cwd: ctx.cwd, timeout: 4000, maxBuffer: 2**20 });
        try {
          void refreshUsage();
          const stat = await git('diff', '--no-ext-diff', '--no-renames', '--numstat', '-z', 'HEAD', '--');
          let plus = 0, minus = 0;
          for (const row of stat.stdout.split('\0')) {
            const [a, d] = row.split('\t');
            plus += Number(a) || 0; minus += Number(d) || 0;
          }
          diff = stat.code ? '—' : `+${plus} -${minus}`;
        } catch { diff = '—'; }
        finally { busy = false; if (active) tui.requestRender(); }
      };
      redraw = () => tui.requestRender();
      void refresh();
      const timer = setInterval(refresh, 15000);
      const started = Date.parse(ctx.sessionManager.getHeader()?.timestamp ?? '') || Date.now();
      let leaf: string | null | undefined, cost = 0;
      const statusKey = '00-extended-statusline';
      let lastLine: string | undefined;
      return {
        invalidate() {},
        dispose() { active = false; clearInterval(timer); redraw = () => {}; ctx.ui.setStatus(statusKey, undefined); },
        render(width: number) {
          const usage = ctx.getContextUsage(), model = ctx.model;
          const capacity = usage?.contextWindow ?? model?.contextWindow;
          const cap = capacity && capacity % 1000000 === 0 ? `${capacity / 1000000}M` : capacity ? tokens(capacity) : '—';
          const pct = usage?.percent, bars = Math.min(20, Math.max(0, Math.round((pct ?? 0) / 5)));
          const meter = `[${'█'.repeat(bars)}${'░'.repeat(20 - bars)}] ${pct == null ? '—' : Math.round(pct) + '%'} ${usage?.tokens == null ? '—' : tokens(usage.tokens)} / ${capacity ? tokens(capacity) : '—'} tokens`;
          const limits = `7d ${quotas.get(model?.provider ?? '') ?? '— (reset —)'}`;
          if (leaf !== ctx.sessionManager.getLeafId()) {
            leaf = ctx.sessionManager.getLeafId(); cost = 0;
            for (const e of ctx.sessionManager.getBranch()) if (e.type === 'message' && e.message.role === 'assistant') cost += e.message.usage.cost.total;
          }
          const mins = Math.max(0, Math.floor((Date.now() - started) / 60000));
          const tail = `${limits} | ${diff} | ⏱ ${Math.floor(mins / 60)}h${pad(mins % 60)}m | $${cost.toFixed(2)}`;
          const head = `${model?.name ?? model?.id ?? '—'} (${cap} context) [${pi.getThinkingLevel()}] ${meter}`;
          const room = width - visibleWidth(tail) - 3;
          const line = room > 4 ? `${truncateToWidth(head, room)} • ${tail}` : truncateToWidth(tail, width);
          if (lastLine !== line) {
            lastLine = line;
            ctx.ui.setStatus(statusKey, line);
          }
          return [];
        },
      };
    }, { placement: 'belowEditor' });
  });
}
