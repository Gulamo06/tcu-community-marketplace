-- ============================================================
-- TCU Community Platform — Migration Script
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- ============================================================
-- IMPORTANT: Run PART 1 first, then PART 2 as a separate query.
-- They cannot be combined because ALTER TYPE...ADD VALUE cannot
-- run inside a transaction block.
-- ============================================================


-- ════════════════════════════════════════════════════════════
-- PART 1 — Run this block alone first, then click Run.
-- Adds 'donation' to the item_category ENUM (if still an ENUM).
-- If your category column is already TEXT, skip this entirely.
-- ════════════════════════════════════════════════════════════

ALTER TYPE item_category ADD VALUE IF NOT EXISTS 'donation';


-- ════════════════════════════════════════════════════════════
-- PART 2 — After Part 1 succeeds, run everything below.
-- ════════════════════════════════════════════════════════════


-- ────────────────────────────────────────────────────────────
-- 1. PROFILES — add missing columns
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email  TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS status TEXT DEFAULT 'active';

-- Apply the status constraint (drop first so re-running is safe)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_status_check
  CHECK (status IN ('active', 'pending_verification', 'id_submitted', 'banned'));


-- ────────────────────────────────────────────────────────────
-- 2. ITEMS — add missing columns
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS condition     TEXT;
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS product_cat   TEXT;
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS don_condition TEXT;


-- ────────────────────────────────────────────────────────────
-- 3. ITEMS — fix category column
--    If category is still typed as item_category ENUM,
--    convert it to TEXT so 'donation' rows can be inserted.
--    Skip if it is already TEXT (check: \d public.items in psql).
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
  -- Only convert if the column is still the ENUM type
  IF EXISTS (
    SELECT 1
    FROM information_schema.columns
    WHERE table_schema = 'public'
      AND table_name   = 'items'
      AND column_name  = 'category'
      AND udt_name     = 'item_category'
  ) THEN
    ALTER TABLE public.items ALTER COLUMN category TYPE TEXT USING category::TEXT;
    ALTER TABLE public.items DROP CONSTRAINT IF EXISTS items_category_check;
    ALTER TABLE public.items ADD CONSTRAINT items_category_check
      CHECK (category IN ('exchange', 'lost', 'found', 'donation'));
  END IF;
END $$;


-- ────────────────────────────────────────────────────────────
-- 4. AI_LOGS — create table if it does not exist
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_logs (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  message    TEXT        NOT NULL,
  response   TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_ai_logs_user_id ON public.ai_logs(user_id);

ALTER TABLE public.ai_logs ENABLE ROW LEVEL SECURITY;

-- Drop before re-creating so this script is safe to re-run
DROP POLICY IF EXISTS "ai_logs_owner_read"   ON public.ai_logs;
DROP POLICY IF EXISTS "ai_logs_auth_insert"  ON public.ai_logs;

CREATE POLICY "ai_logs_owner_read"
  ON public.ai_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "ai_logs_auth_insert"
  ON public.ai_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 5. ITEMS RLS — add missing policies (idempotent)
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "items_public_read"     ON public.items;
DROP POLICY IF EXISTS "items_verified_insert" ON public.items;
DROP POLICY IF EXISTS "items_owner_update"    ON public.items;
DROP POLICY IF EXISTS "items_owner_delete"    ON public.items;

CREATE POLICY "items_public_read"
  ON public.items FOR SELECT
  USING (is_active = true);

CREATE POLICY "items_verified_insert"
  ON public.items FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND auth.uid() = owner_id
    AND EXISTS (
      SELECT 1 FROM public.profiles
      WHERE id = auth.uid() AND is_verified = true
    )
  );

CREATE POLICY "items_owner_update"
  ON public.items FOR UPDATE
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "items_owner_delete"
  ON public.items FOR DELETE
  USING (auth.uid() = owner_id);


-- ────────────────────────────────────────────────────────────
-- 6. PROFILES RLS — ensure policies exist (idempotent)
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "profiles_public_read"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_insert"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update"  ON public.profiles;

CREATE POLICY "profiles_public_read"
  ON public.profiles FOR SELECT
  USING (true);

CREATE POLICY "profiles_self_insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_self_update"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);


-- ────────────────────────────────────────────────────────────
-- Done. Verify with:
--   SELECT column_name, data_type FROM information_schema.columns
--   WHERE table_schema = 'public' AND table_name = 'profiles'
--   ORDER BY ordinal_position;
-- ────────────────────────────────────────────────────────────
