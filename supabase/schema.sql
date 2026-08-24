-- 在 Supabase 控制台 → SQL Editor 里整段执行一次即可。
--
-- 为什么持仓存成 jsonb 而不是拆成列：一条持仓带着 dividendRecords 和
-- positionAdjustments 两个还在演进的数组，拆列意味着三张表加连接查询，前端
-- 那套同步计算逻辑要整个重写。存 jsonb 后同步层只剩 upsert 一行，加字段也
-- 不用改数据库。代价是查不了「所有人的 AAPL 持仓」——这个 app 不需要。

create table if not exists public.holdings (
  id          text        primary key,
  user_id     uuid        not null references auth.users on delete cascade default auth.uid(),
  payload     jsonb       not null,
  updated_at  timestamptz not null default now()
);

create index if not exists holdings_user_id_idx on public.holdings (user_id);

-- 行级安全是这套方案的全部防线：anon key 会明文出现在前端 JS 里，任何人都拿
-- 得到。没有下面这段策略，拿到 key 就等于拿到所有人的持仓。
alter table public.holdings enable row level security;

drop policy if exists "holdings are private to their owner" on public.holdings;
create policy "holdings are private to their owner"
  on public.holdings
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
