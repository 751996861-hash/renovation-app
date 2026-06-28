-- ============================================================
-- 装修记账 App — Supabase Database Schema (FIXED)
-- 在 Supabase Dashboard → SQL Editor 中执行此文件
-- 先删除旧版本（如果执行过之前的版本）
-- ============================================================

-- 先清理旧 trigger 和 function（如果存在）
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS handle_new_user();

-- 删除旧表（按依赖顺序）
DROP TABLE IF EXISTS budget_settings;
DROP TABLE IF EXISTS cycles;
DROP TABLE IF EXISTS reminders;
DROP TABLE IF EXISTS contracts;
DROP TABLE IF EXISTS expenses;
DROP TABLE IF EXISTS sub_categories;
DROP TABLE IF EXISTS categories;

-- ============================================================
-- 1. 分类表
-- ============================================================
CREATE TABLE categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  budget DECIMAL(12,2) DEFAULT 0,
  icon_color TEXT DEFAULT '#34D399',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own categories" ON categories FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 2. 子分类表
-- ============================================================
CREATE TABLE sub_categories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  category_id UUID REFERENCES categories(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  budget DECIMAL(12,2) DEFAULT 0,
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE sub_categories ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own sub_categories" ON sub_categories FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 3. 支出记录表
-- ============================================================
CREATE TABLE expenses (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  category_id UUID REFERENCES categories(id),
  sub_category_id UUID REFERENCES sub_categories(id),
  name TEXT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  source TEXT DEFAULT '线下',
  date DATE NOT NULL DEFAULT CURRENT_DATE,
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE expenses ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own expenses" ON expenses FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 4. 合同款项表
-- ============================================================
CREATE TABLE contracts (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  amount DECIMAL(12,2) NOT NULL,
  payment_date DATE,
  status TEXT DEFAULT '待付款',
  type TEXT DEFAULT '合同款项',
  notes TEXT DEFAULT '',
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE contracts ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own contracts" ON contracts FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 5. 待办提醒表
-- ============================================================
CREATE TABLE reminders (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT DEFAULT '',
  deadline DATE,
  priority TEXT DEFAULT '普通',
  status TEXT DEFAULT '进行中',
  created_at TIMESTAMPTZ DEFAULT now(),
  completed_at TIMESTAMPTZ
);
ALTER TABLE reminders ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own reminders" ON reminders FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 6. 施工周期表
-- ============================================================
CREATE TABLE cycles (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  budget DECIMAL(12,2) NOT NULL DEFAULT 0,
  spent DECIMAL(12,2) NOT NULL DEFAULT 0,
  status TEXT DEFAULT '未开始',
  sort_order INT DEFAULT 0,
  created_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE cycles ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own cycles" ON cycles FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 7. 总预算设置表
-- ============================================================
CREATE TABLE budget_settings (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE UNIQUE,
  total_budget DECIMAL(12,2) NOT NULL DEFAULT 200000,
  created_at TIMESTAMPTZ DEFAULT now(),
  updated_at TIMESTAMPTZ DEFAULT now()
);
ALTER TABLE budget_settings ENABLE ROW LEVEL SECURITY;
CREATE POLICY "Users see own budget" ON budget_settings FOR ALL USING (auth.uid() = user_id);

-- ============================================================
-- 8. 新用户触发器（简化版 — 避免 CROSS JOIN 问题）
-- ============================================================
CREATE OR REPLACE FUNCTION handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cat_hard UUID;
  v_cat_soft UUID;
  v_cat_labor UUID;
  v_cat_design UUID;
BEGIN
  -- 插入默认预算
  INSERT INTO budget_settings (user_id, total_budget)
  VALUES (NEW.id, 200000);

  -- 插入默认分类，并记住 ID
  INSERT INTO categories (user_id, name, budget, icon_color, sort_order)
  VALUES (NEW.id, '硬装', 120000, '#34D399', 0)
  RETURNING id INTO v_cat_hard;

  INSERT INTO categories (user_id, name, budget, icon_color, sort_order)
  VALUES (NEW.id, '软装', 80000, '#60A5FA', 1)
  RETURNING id INTO v_cat_soft;

  INSERT INTO categories (user_id, name, budget, icon_color, sort_order)
  VALUES (NEW.id, '人工', 0, '#FBBF24', 2)
  RETURNING id INTO v_cat_labor;

  INSERT INTO categories (user_id, name, budget, icon_color, sort_order)
  VALUES (NEW.id, '设计', 0, '#A78BFA', 3)
  RETURNING id INTO v_cat_design;

  -- 硬装子分类
  INSERT INTO sub_categories (user_id, category_id, name, sort_order) VALUES
    (NEW.id, v_cat_hard, '瓷砖', 0),
    (NEW.id, v_cat_hard, '水电', 1),
    (NEW.id, v_cat_hard, '防水', 2),
    (NEW.id, v_cat_hard, '瓦工', 3),
    (NEW.id, v_cat_hard, '油漆', 4),
    (NEW.id, v_cat_hard, '其他硬装', 5);

  -- 软装子分类
  INSERT INTO sub_categories (user_id, category_id, name, sort_order) VALUES
    (NEW.id, v_cat_soft, '家具', 0),
    (NEW.id, v_cat_soft, '灯具', 1),
    (NEW.id, v_cat_soft, '窗帘', 2),
    (NEW.id, v_cat_soft, '家电', 3),
    (NEW.id, v_cat_soft, '其他软装', 4);

  -- 人工子分类
  INSERT INTO sub_categories (user_id, category_id, name, sort_order)
  VALUES (NEW.id, v_cat_labor, '施工人工', 0);

  -- 设计子分类
  INSERT INTO sub_categories (user_id, category_id, name, sort_order)
  VALUES (NEW.id, v_cat_design, '设计费', 0);

  -- 默认施工周期
  INSERT INTO cycles (user_id, name, budget, spent, status, sort_order) VALUES
    (NEW.id, '主体改造期', 20000, 0, '未开始', 0),
    (NEW.id, '水电施工期', 15000, 0, '未开始', 1),
    (NEW.id, '泥木工程期', 25000, 0, '未开始', 2),
    (NEW.id, '油漆涂料期', 10000, 0, '未开始', 3),
    (NEW.id, '安装工程期', 15000, 0, '未开始', 4),
    (NEW.id, '软装采购期', 30000, 0, '未开始', 5);

  RETURN NEW;
END;
$$;

CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION handle_new_user();

-- ============================================================
-- 9. 开启实时订阅
-- ============================================================
ALTER PUBLICATION supabase_realtime ADD TABLE expenses;
ALTER PUBLICATION supabase_realtime ADD TABLE reminders;
