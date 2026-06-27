-- ============================================================
-- 装修记账 App — Supabase Database Schema
-- 在 Supabase Dashboard → SQL Editor 中执行此文件
-- ============================================================

-- 1. 启用 Row Level Security
-- 每个用户只能看到自己的数据

-- 2. 分类表
CREATE TABLE IF NOT EXISTS categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,            -- 硬装/软装/人工/设计
  budget DECIMAL(12,2) DEFAULT 0,
  icon_color TEXT DEFAULT '#34D399',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own categories" ON categories FOR ALL USING (auth.uid() = user_id);

-- 3. 子分类表
CREATE TABLE IF NOT EXISTS sub_categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  category_id UUID REFERENCES categories(id) ON DELETE CASCADE,
  name TEXT NOT NULL,            -- 瓷砖/水电/防水等
  budget DECIMAL(12,2) DEFAULT 0,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE sub_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own sub_categories" ON sub_categories FOR ALL USING (auth.uid() = user_id);

-- 4. 支出记录表
CREATE TABLE IF NOT EXISTS expenses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  category_id UUID REFERENCES categories(id),
  sub_category_id UUID REFERENCES sub_categories(id),
  name TEXT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  source TEXT DEFAULT '线下',     -- 京东/淘宝/微信/线下/银行
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own expenses" ON expenses FOR ALL USING (auth.uid() = user_id);

-- 5. 合同款项表
CREATE TABLE IF NOT EXISTS contracts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,           -- 首期款/中期款/尾款
  amount DECIMAL(12,2) NOT NULL,
  payment_date DATE,
  status TEXT DEFAULT '待付款',  -- 待付款/已付款
  type TEXT DEFAULT '合同款项',   -- 合同款项/自费增项
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own contracts" ON contracts FOR ALL USING (auth.uid() = user_id);

-- 6. 待办提醒表
CREATE TABLE IF NOT EXISTS reminders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  deadline DATE,
  priority TEXT DEFAULT '普通',  -- 紧急/重要/普通
  status TEXT DEFAULT '进行中',  -- 进行中/已完成
  related_expense_id UUID REFERENCES expenses(id),
  created_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own reminders" ON reminders FOR ALL USING (auth.uid() = user_id);

-- 7. 施工周期表
CREATE TABLE IF NOT EXISTS cycles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,            -- 主体改造期/水电施工期等
  budget DECIMAL(12,2) NOT NULL DEFAULT 0,
  spent DECIMAL(12,2) NOT NULL DEFAULT 0,
  status TEXT DEFAULT '未开始',  -- 未开始/进行中/已结束
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE cycles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own cycles" ON cycles FOR ALL USING (auth.uid() = user_id);

-- 8. 总预算设置表
CREATE TABLE IF NOT EXISTS budget_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  total_budget DECIMAL(12,2) NOT NULL DEFAULT 200000,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE budget_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own budget" ON budget_settings FOR ALL USING (auth.uid() = user_id);

-- 9. 插入默认施工周期（新用户注册时触发）
-- 通过 trigger 在新用户注册后自动插入

-- 为新用户创建默认数据的函数
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  -- 插入默认预算
  INSERT INTO budget_settings (user_id, total_budget) VALUES (NEW.id, 200000);

  -- 插入默认分类
  INSERT INTO categories (user_id, name, budget, icon_color, sort_order) VALUES
    (NEW.id, '硬装', 120000, '#34D399', 0),
    (NEW.id, '软装', 80000, '#60A5FA', 1),
    (NEW.id, '人工', 0, '#FBBF24', 2),
    (NEW.id, '设计', 0, '#A78BFA', 3);

  -- 插入默认子分类
  INSERT INTO sub_categories (user_id, category_id, name, sort_order)
  SELECT
    NEW.id,
    c.id,
    s.name,
    s.sort_order
  FROM (VALUES ('瓷砖',0),('水电',1),('防水',2),('瓦工',3),('油漆',4),('其他硬装',5)) AS s(name, sort_order)
  CROSS JOIN (SELECT id FROM categories WHERE user_id = NEW.id AND name = '硬装') AS c;

  INSERT INTO sub_categories (user_id, category_id, name, sort_order)
  SELECT
    NEW.id,
    c.id,
    s.name,
    s.sort_order
  FROM (VALUES ('家具',0),('灯具',1),('窗帘',2),('家电',3),('其他软装',4)) AS s(name, sort_order)
  CROSS JOIN (SELECT id FROM categories WHERE user_id = NEW.id AND name = '软装') AS c;

  INSERT INTO sub_categories (user_id, category_id, name, sort_order)
  SELECT NEW.id, c.id, '施工人工', 0
  FROM (SELECT id FROM categories WHERE user_id = NEW.id AND name = '人工') AS c;

  INSERT INTO sub_categories (user_id, category_id, name, sort_order)
  SELECT NEW.id, c.id, '设计费', 0
  FROM (SELECT id FROM categories WHERE user_id = NEW.id AND name = '设计') AS c;

  -- 插入默认施工周期
  INSERT INTO cycles (user_id, name, budget, spent, status, sort_order) VALUES
    (NEW.id, '主体改造期', 20000, 0, '未开始', 0),
    (NEW.id, '水电施工期', 15000, 0, '未开始', 1),
    (NEW.id, '泥木工程期', 25000, 0, '未开始', 2),
    (NEW.id, '油漆涂料期', 10000, 0, '未开始', 3),
    (NEW.id, '安装工程期', 15000, 0, '未开始', 4),
    (NEW.id, '软装采购期', 30000, 0, '未开始', 5);

  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

CREATE OR REPLACE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- 10. 开启实时订阅（expenses 和 reminders）
ALTER PUBLICATION supabase_realtime ADD TABLE expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE reminders;
