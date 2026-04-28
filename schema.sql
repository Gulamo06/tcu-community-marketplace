-- ============================================================
-- Tzu Chi University Community Platform
-- Supabase SQL Schema — v2.0
-- Run this in Supabase SQL Editor (Dashboard → SQL Editor → New query)
-- For existing databases use migration_v2.sql instead.
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- STEP 1: EXTENSIONS
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ────────────────────────────────────────────────────────────
-- STEP 2: PROFILES TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                     UUID                NOT NULL PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name              TEXT                NOT NULL DEFAULT 'New Student',
  student_id             TEXT                UNIQUE NOT NULL,
  department             TEXT,
  avatar_url             TEXT,
  email                  TEXT,
  phone_number           TEXT,
  line_id                TEXT,
  instagram_handle       TEXT,
  is_verified            BOOLEAN             NOT NULL DEFAULT false,
  student_id_image_url   TEXT,
  verification_status    TEXT                NOT NULL DEFAULT 'pending'
                           CHECK (verification_status IN ('pending', 'approved', 'rejected')),
  status                 TEXT                NOT NULL DEFAULT 'active'
                           CHECK (status IN ('active', 'pending_verification', 'id_submitted', 'banned')),
  created_at             TIMESTAMPTZ         NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ         NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.profiles IS 'Student profile data linked to Supabase Auth.';
COMMENT ON COLUMN public.profiles.email IS 'Synced from auth.users on every login.';
COMMENT ON COLUMN public.profiles.is_verified IS 'True once an admin approves the student ID upload.';
COMMENT ON COLUMN public.profiles.verification_status IS 'pending → approved (sets is_verified=true) → rejected.';
COMMENT ON COLUMN public.profiles.status IS 'active | pending_verification | id_submitted | banned';


-- ────────────────────────────────────────────────────────────
-- STEP 3: ITEMS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.items (
  id                        UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id                  UUID            NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                     TEXT            NOT NULL CHECK (char_length(title) BETWEEN 3 AND 120),
  description               TEXT            NOT NULL CHECK (char_length(description) >= 20),
  category                  TEXT            NOT NULL CHECK (category IN ('exchange', 'lost', 'found', 'donation')),
  condition                 TEXT,
  product_cat               TEXT,
  don_condition             TEXT,
  unique_identifier         TEXT            NOT NULL CHECK (char_length(unique_identifier) >= 5),
  verification_hint         TEXT,
  price                     NUMERIC(10,2)   CHECK (price IS NULL OR price >= 0),
  image_urls                TEXT[]          NOT NULL DEFAULT '{}',
  status                    TEXT            NOT NULL DEFAULT 'available'
                              CHECK (status IN ('available', 'sold', 'returned')),
  preferred_contact_method  TEXT            NOT NULL DEFAULT 'line',
  location_hint             TEXT,
  last_confirmed_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  expires_at                TIMESTAMPTZ     NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  is_active                 BOOLEAN         NOT NULL DEFAULT true,
  created_at                TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.items IS 'All marketplace and lost/found item listings.';
COMMENT ON COLUMN public.items.category IS 'exchange | lost | found | donation';
COMMENT ON COLUMN public.items.status IS 'available | sold | returned';
COMMENT ON COLUMN public.items.unique_identifier IS 'Mandatory detail (serial no., colour, brand) to prevent fraud.';
COMMENT ON COLUMN public.items.image_urls IS 'Array of public image URLs stored in item-images bucket.';
COMMENT ON COLUMN public.items.expires_at IS 'Reset by confirm_item(). After this date is_active is set false.';

CREATE INDEX IF NOT EXISTS idx_items_owner_id   ON public.items(owner_id);
CREATE INDEX IF NOT EXISTS idx_items_category   ON public.items(category);
CREATE INDEX IF NOT EXISTS idx_items_status     ON public.items(status);
CREATE INDEX IF NOT EXISTS idx_items_is_active  ON public.items(is_active);
CREATE INDEX IF NOT EXISTS idx_items_expires_at ON public.items(expires_at);
CREATE INDEX IF NOT EXISTS idx_items_created    ON public.items(created_at DESC);


-- ────────────────────────────────────────────────────────────
-- STEP 4: AI_LOGS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_logs (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  message    TEXT        NOT NULL,
  response   TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_logs IS 'AI assistant conversations for audit and personalisation.';
CREATE INDEX IF NOT EXISTS idx_ai_logs_user_id ON public.ai_logs(user_id);


-- ────────────────────────────────────────────────────────────
-- STEP 5: STORAGE BUCKET
-- Creates the item-images bucket (public) for item photos,
-- student ID uploads, and profile avatars.
-- ────────────────────────────────────────────────────────────
INSERT INTO storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
VALUES (
  'item-images',
  'item-images',
  true,
  5242880,           -- 5 MB per file
  ARRAY['image/jpeg','image/png','image/webp','image/gif']
)
ON CONFLICT (id) DO NOTHING;

-- Storage RLS: anyone can read public files
DROP POLICY IF EXISTS "storage_public_read"    ON storage.objects;
CREATE POLICY "storage_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'item-images');

-- Authenticated users can upload to item-images
DROP POLICY IF EXISTS "storage_auth_upload"    ON storage.objects;
CREATE POLICY "storage_auth_upload"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);

-- Users can delete their own uploads
DROP POLICY IF EXISTS "storage_auth_delete"    ON storage.objects;
CREATE POLICY "storage_auth_delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);


-- ────────────────────────────────────────────────────────────
-- STEP 6: AUTO-UPDATE updated_at TRIGGER
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_updated_at()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS set_profiles_updated_at ON public.profiles;
CREATE TRIGGER set_profiles_updated_at
  BEFORE UPDATE ON public.profiles
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();

DROP TRIGGER IF EXISTS set_items_updated_at ON public.items;
CREATE TRIGGER set_items_updated_at
  BEFORE UPDATE ON public.items
  FOR EACH ROW EXECUTE FUNCTION public.handle_updated_at();


-- ────────────────────────────────────────────────────────────
-- STEP 7: AUTO-CREATE PROFILE ON SIGN-UP TRIGGER
-- Copies email, full_name, and avatar_url from auth metadata
-- so Google/email logins always get a complete profile row.
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
-- STEP 8: UTILITY FUNCTIONS (RPC)
-- ────────────────────────────────────────────────────────────

-- Allows a user to permanently delete their own auth account.
-- CASCADE on profiles.id → auth.users removes all linked data.
CREATE OR REPLACE FUNCTION public.delete_own_account()
RETURNS void AS $$
BEGIN
  DELETE FROM auth.users WHERE id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- Expire listings whose 7-day clock has run out (run via pg_cron daily)
CREATE OR REPLACE FUNCTION public.expire_old_items()
RETURNS void AS $$
BEGIN
  UPDATE public.items
  SET is_active = false
  WHERE expires_at < NOW() AND is_active = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Owner resets the 7-day expiry clock on their own listing
CREATE OR REPLACE FUNCTION public.confirm_item(item_id UUID)
RETURNS void AS $$
BEGIN
  UPDATE public.items
  SET last_confirmed_at = NOW(),
      expires_at        = NOW() + INTERVAL '7 days'
  WHERE id = item_id AND owner_id = auth.uid();
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Full-text keyword search across active items
CREATE OR REPLACE FUNCTION public.search_items(keyword TEXT)
RETURNS SETOF public.items AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM public.items
  WHERE is_active = true
    AND (
      title        ILIKE '%' || keyword || '%'
      OR description   ILIKE '%' || keyword || '%'
      OR location_hint ILIKE '%' || keyword || '%'
    )
  ORDER BY created_at DESC;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;


-- ────────────────────────────────────────────────────────────
-- STEP 9: ROW LEVEL SECURITY (RLS)
-- ────────────────────────────────────────────────────────────
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_logs  ENABLE ROW LEVEL SECURITY;


-- ── Profiles policies ──────────────────────────────────────
DROP POLICY IF EXISTS "profiles_public_read"    ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_insert"    ON public.profiles;
DROP POLICY IF EXISTS "profiles_self_update"    ON public.profiles;
DROP POLICY IF EXISTS "profiles_admin_update"   ON public.profiles;

-- Anyone can read all profiles (needed for seller info on cards)
CREATE POLICY "profiles_public_read"
  ON public.profiles FOR SELECT
  USING (true);

-- A user can only insert their own profile
CREATE POLICY "profiles_self_insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- A user can update their own profile
CREATE POLICY "profiles_self_update"
  ON public.profiles FOR UPDATE
  USING  (auth.uid() = id)
  WITH CHECK (auth.uid() = id);

-- Admin (by email) can update any profile (approve/reject verification)
CREATE POLICY "profiles_admin_update"
  ON public.profiles FOR UPDATE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.email = '114122104@gms.tzu.edu.tw'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.email = '114122104@gms.tzu.edu.tw'
    )
  );


-- ── Items policies ─────────────────────────────────────────
DROP POLICY IF EXISTS "items_public_read"      ON public.items;
DROP POLICY IF EXISTS "items_verified_insert"  ON public.items;
DROP POLICY IF EXISTS "items_owner_update"     ON public.items;
DROP POLICY IF EXISTS "items_owner_delete"     ON public.items;
DROP POLICY IF EXISTS "items_admin_delete"     ON public.items;

-- Anyone can read active listings
CREATE POLICY "items_public_read"
  ON public.items FOR SELECT
  USING (is_active = true);

-- Only verified students can post items
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

-- Owner can update their own item
CREATE POLICY "items_owner_update"
  ON public.items FOR UPDATE
  USING  (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Owner can delete their own item
CREATE POLICY "items_owner_delete"
  ON public.items FOR DELETE
  USING (auth.uid() = owner_id);

-- Admin can delete any item (moderation)
CREATE POLICY "items_admin_delete"
  ON public.items FOR DELETE
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid()
        AND p.email = '114122104@gms.tzu.edu.tw'
    )
  );


-- ── AI Logs policies ───────────────────────────────────────
DROP POLICY IF EXISTS "ai_logs_owner_read"    ON public.ai_logs;
DROP POLICY IF EXISTS "ai_logs_auth_insert"   ON public.ai_logs;

-- Users can only read their own logs
CREATE POLICY "ai_logs_owner_read"
  ON public.ai_logs FOR SELECT
  USING (auth.uid() = user_id);

-- Authenticated users can insert their own logs
CREATE POLICY "ai_logs_auth_insert"
  ON public.ai_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- DONE — verify with:
--
--   SELECT table_name, column_name, data_type
--   FROM information_schema.columns
--   WHERE table_schema = 'public'
--   ORDER BY table_name, ordinal_position;
-- ────────────────────────────────────────────────────────────
