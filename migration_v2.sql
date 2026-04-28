-- ============================================================
-- TCU Community Platform — Migration v2
-- Run in Supabase SQL Editor on an EXISTING database.
-- Safe to re-run (all statements are idempotent).
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. PROFILES — add any missing columns
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS email             TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_url        TEXT;
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS status            TEXT NOT NULL DEFAULT 'active';
ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS student_id_image_url TEXT;

-- Fix full_name default (old schema had NOT NULL without a DEFAULT)
ALTER TABLE public.profiles ALTER COLUMN full_name SET DEFAULT 'New Student';

-- Status constraint (drop first so re-running is safe)
ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_status_check
  CHECK (status IN ('active', 'pending_verification', 'id_submitted', 'banned'));

-- verification_status as TEXT if still an ENUM
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles'
      AND column_name = 'verification_status' AND udt_name <> 'text'
  ) THEN
    ALTER TABLE public.profiles
      ALTER COLUMN verification_status TYPE TEXT USING verification_status::TEXT;
  END IF;
END $$;

ALTER TABLE public.profiles DROP CONSTRAINT IF EXISTS profiles_verification_status_check;
ALTER TABLE public.profiles ADD CONSTRAINT profiles_verification_status_check
  CHECK (verification_status IN ('pending', 'approved', 'rejected'));


-- ────────────────────────────────────────────────────────────
-- 2. ITEMS — add missing columns & fix category
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS condition     TEXT;
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS product_cat   TEXT;
ALTER TABLE public.items ADD COLUMN IF NOT EXISTS don_condition TEXT;

-- Convert category from ENUM to TEXT (if not already TEXT)
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'items'
      AND column_name = 'category' AND udt_name = 'item_category'
  ) THEN
    ALTER TABLE public.items ALTER COLUMN category TYPE TEXT USING category::TEXT;
  END IF;
END $$;

ALTER TABLE public.items DROP CONSTRAINT IF EXISTS items_category_check;
ALTER TABLE public.items ADD CONSTRAINT items_category_check
  CHECK (category IN ('exchange', 'lost', 'found', 'donation'));

ALTER TABLE public.items DROP CONSTRAINT IF EXISTS items_status_check;
ALTER TABLE public.items ADD CONSTRAINT items_status_check
  CHECK (status IN ('available', 'sold', 'returned'));


-- ────────────────────────────────────────────────────────────
-- 3. AI_LOGS — create table if missing
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


-- ────────────────────────────────────────────────────────────
-- 4. STORAGE BUCKET — item-images (public, 5 MB limit)
-- ────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'item-images',
  'item-images',
  true,
  5242880,
  ARRAY['image/jpeg','image/png','image/webp','image/gif']
)
ON CONFLICT (id) DO NOTHING;

DROP POLICY IF EXISTS "storage_public_read"  ON storage.objects;
CREATE POLICY "storage_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'item-images');

DROP POLICY IF EXISTS "storage_auth_upload"  ON storage.objects;
CREATE POLICY "storage_auth_upload"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "storage_auth_delete"  ON storage.objects;
CREATE POLICY "storage_auth_delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);


-- ────────────────────────────────────────────────────────────
-- 5. FIX handle_new_user TRIGGER
-- Now copies email and avatar_url from Google/email OAuth metadata.
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, student_id, email, avatar_url)
  VALUES (
    NEW.id,
    COALESCE(
      NEW.raw_user_meta_data->>'full_name',
      NEW.raw_user_meta_data->>'name',
      'New Student'
    ),
    COALESCE(
      NEW.raw_user_meta_data->>'student_id',
      'PENDING-' || substr(NEW.id::text, 1, 8)
    ),
    NEW.email,
    COALESCE(
      NEW.raw_user_meta_data->>'avatar_url',
      NEW.raw_user_meta_data->>'picture'
    )
  )
  ON CONFLICT (id) DO NOTHING;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ────────────────────────────────────────────────────────────
-- 6. RLS POLICIES (all idempotent — drop then recreate)
-- ────────────────────────────────────────────────────────────

-- Enable RLS (safe even if already enabled)
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_logs  ENABLE ROW LEVEL SECURITY;


-- ── Profiles ──
DROP POLICY IF EXISTS "profiles_public_read"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_insert"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update"  ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_update" ON public.profiles;

CREATE POLICY "profiles_public_read"
  ON public.profiles FOR SELECT USING (true);

CREATE POLICY "profiles_self_insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

CREATE POLICY "profiles_self_update"
  ON public.profiles FOR UPDATE
  USING  (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Admin can update ANY profile (approve/reject student verification)
CREATE POLICY "profiles_admin_update"
  ON public.profiles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.email = '114122104@gms.tcu.edu.tw'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.email = '114122104@gms.tcu.edu.tw'
    )
  );


-- ── Items ──
DROP POLICY IF EXISTS "items_public_read"      ON public.items;
DROP POLICY IF EXISTS "items_verified_insert"  ON public.items;
DROP POLICY IF EXISTS "items_owner_update"     ON public.items;
DROP POLICY IF EXISTS "items_owner_delete"     ON public.items;
DROP POLICY IF EXISTS "items_admin_delete"     ON public.items;

CREATE POLICY "items_public_read"
  ON public.items FOR SELECT USING (is_active = true);

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
  USING  (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

CREATE POLICY "items_owner_delete"
  ON public.items FOR DELETE
  USING (auth.uid() = owner_id);

-- Admin can delete any item (moderation)
CREATE POLICY "items_admin_delete"
  ON public.items FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.email = '114122104@gms.tcu.edu.tw'
    )
  );


-- ── AI Logs ──
DROP POLICY IF EXISTS "ai_logs_owner_read"   ON public.ai_logs;
DROP POLICY IF EXISTS "ai_logs_auth_insert"  ON public.ai_logs;

CREATE POLICY "ai_logs_owner_read"
  ON public.ai_logs FOR SELECT
  USING (auth.uid() = user_id);

CREATE POLICY "ai_logs_auth_insert"
  ON public.ai_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- 7. ACCOUNT SELF-DELETION RPC
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void AS $$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- DONE — verify with:
--
--   SELECT table_name, column_name, data_type
--   FROM information_schema.columns
--   WHERE table_schema = 'public'
--   ORDER BY table_name, ordinal_position;
-- ────────────────────────────────────────────────────────────
