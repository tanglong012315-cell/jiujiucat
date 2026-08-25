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

-- 用户资料（自定义用户名 + 头像）。和持仓分表：holdings 的 payload 是一整条
-- 持仓，把用户名塞进去等于每条持仓存一份副本，改一次名要重写所有行。
-- avatar 存的是 Remix Icon 的类名（如 ri-bear-smile-line），前端有白名单校验。
create table if not exists public.profiles (
  user_id       uuid        primary key references auth.users on delete cascade default auth.uid(),
  display_name  text,
  avatar        text,
  updated_at    timestamptz not null default now()
);

-- 同上：anon key 是公开的，没有这段策略，拿到 key 就能读到所有人的用户名。
alter table public.profiles enable row level security;

drop policy if exists "profiles are private to their owner" on public.profiles;
create policy "profiles are private to their owner"
  on public.profiles
  for all
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);
