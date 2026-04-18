-- ============================================================
-- Tzu Chi University Community Platform
-- Supabase SQL Schema — v1.0
-- ============================================================

-- ────────────────────────────────────────────────────────────
-- STEP 1: EXTENSIONS
-- ────────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";


-- ────────────────────────────────────────────────────────────
-- STEP 2: CUSTOM TYPES (ENUMS)
-- ────────────────────────────────────────────────────────────
DO $$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'item_category') THEN
    CREATE TYPE item_category AS ENUM ('exchange', 'lost', 'found');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'item_status') THEN
    CREATE TYPE item_status AS ENUM ('available', 'sold', 'returned');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'verification_status') THEN
    CREATE TYPE verification_status AS ENUM ('pending', 'approved', 'rejected');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'contact_method') THEN
    CREATE TYPE contact_method AS ENUM ('line', 'instagram', 'phone', 'chat');
  END IF;
END
$$;


-- ────────────────────────────────────────────────────────────
-- STEP 3: PROFILES TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.profiles (
  id                     UUID                 PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  full_name              TEXT                 NOT NULL,
  student_id             TEXT                 UNIQUE NOT NULL,
  department             TEXT,
  avatar_url             TEXT,
  phone_number           TEXT,
  line_id                TEXT,
  instagram_handle       TEXT,
  is_verified            BOOLEAN              NOT NULL DEFAULT false,
  student_id_image_url   TEXT,
  verification_status    verification_status  NOT NULL DEFAULT 'pending',
  created_at             TIMESTAMPTZ          NOT NULL DEFAULT NOW(),
  updated_at             TIMESTAMPTZ          NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.profiles                           IS 'Student profile data, linked to Supabase Auth.';
COMMENT ON COLUMN public.profiles.student_id               IS 'Official university student ID number.';
COMMENT ON COLUMN public.profiles.line_id                  IS 'LINE messenger handle for direct contact.';
COMMENT ON COLUMN public.profiles.instagram_handle         IS 'Instagram username without the @ symbol.';
COMMENT ON COLUMN public.profiles.is_verified              IS 'True once an admin approves the student ID upload.';
COMMENT ON COLUMN public.profiles.student_id_image_url     IS 'URL of student ID card image for admin verification.';
COMMENT ON COLUMN public.profiles.verification_status      IS 'pending → approved (sets is_verified=true) → rejected.';


-- ────────────────────────────────────────────────────────────
-- STEP 4: ITEMS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.items (
  id                        UUID            PRIMARY KEY DEFAULT gen_random_uuid(),
  owner_id                  UUID            NOT NULL REFERENCES public.profiles(id) ON DELETE CASCADE,
  title                     TEXT            NOT NULL CHECK (char_length(title) BETWEEN 3 AND 120),
  description               TEXT            NOT NULL CHECK (char_length(description) >= 20),
  category                  item_category   NOT NULL,
  unique_identifier         TEXT            NOT NULL CHECK (char_length(unique_identifier) >= 5),
  verification_hint         TEXT,
  price                     NUMERIC(10,2)   CHECK (price IS NULL OR price >= 0),
  image_urls                TEXT[]          NOT NULL DEFAULT '{}',
  status                    item_status     NOT NULL DEFAULT 'available',
  preferred_contact_method  contact_method  NOT NULL DEFAULT 'line',
  location_hint             TEXT,
  last_confirmed_at         TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  expires_at                TIMESTAMPTZ     NOT NULL DEFAULT (NOW() + INTERVAL '7 days'),
  is_active                 BOOLEAN         NOT NULL DEFAULT true,
  created_at                TIMESTAMPTZ     NOT NULL DEFAULT NOW(),
  updated_at                TIMESTAMPTZ     NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE  public.items                           IS 'All marketplace and lost/found item listings.';
COMMENT ON COLUMN public.items.unique_identifier         IS 'Mandatory distinguishing detail (serial no., color, brand) to prevent fraud.';
COMMENT ON COLUMN public.items.verification_hint         IS 'Public hint about the unique identifier (e.g., "scratch on battery cover").';
COMMENT ON COLUMN public.items.image_urls                IS 'Array of public image URLs (upload to Supabase Storage).';
COMMENT ON COLUMN public.items.price                     IS 'NULL for lost/found items. Required for exchange/marketplace listings.';
COMMENT ON COLUMN public.items.preferred_contact_method  IS 'How the poster prefers to be contacted.';
COMMENT ON COLUMN public.items.last_confirmed_at         IS 'Last time the owner confirmed the item is still relevant.';
COMMENT ON COLUMN public.items.expires_at                IS 'Set on insert and reset by confirm_item(). After this date, is_active is set false.';
COMMENT ON COLUMN public.items.is_active                 IS 'False when expired or manually deactivated. Public read only sees is_active=true.';

-- Index for fast filtering
CREATE INDEX IF NOT EXISTS idx_items_owner_id   ON public.items(owner_id);
CREATE INDEX IF NOT EXISTS idx_items_category   ON public.items(category);
CREATE INDEX IF NOT EXISTS idx_items_status     ON public.items(status);
CREATE INDEX IF NOT EXISTS idx_items_is_active  ON public.items(is_active);
CREATE INDEX IF NOT EXISTS idx_items_expires_at ON public.items(expires_at);
CREATE INDEX IF NOT EXISTS idx_items_created    ON public.items(created_at DESC);


-- ────────────────────────────────────────────────────────────
-- STEP 4B: AI_LOGS TABLE
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ai_logs (
  id         UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id    UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  message    TEXT        NOT NULL,
  response   TEXT        NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.ai_logs IS 'Stores AI assistant conversations for audit and personalisation.';

CREATE INDEX IF NOT EXISTS idx_ai_logs_user_id ON public.ai_logs(user_id);


-- ────────────────────────────────────────────────────────────
-- STEP 5: AUTO-UPDATE `updated_at` TRIGGER
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
-- STEP 6: AUTO-CREATE PROFILE ON SIGN-UP TRIGGER
-- ────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER AS $$
BEGIN
  INSERT INTO public.profiles (id, full_name, student_id)
  VALUES (
    NEW.id,
    COALESCE(NEW.raw_user_meta_data->>'full_name', 'New Student'),
    COALESCE(NEW.raw_user_meta_data->>'student_id', 'PENDING-' || substr(NEW.id::text, 1, 8))
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();


-- ────────────────────────────────────────────────────────────
-- STEP 7: EXPIRATION & UTILITY FUNCTIONS (RPC)
-- ────────────────────────────────────────────────────────────

-- Run via Supabase Scheduled Functions (pg_cron) daily to expire old items
CREATE OR REPLACE FUNCTION public.expire_old_items()
RETURNS void AS $$
BEGIN
  UPDATE public.items
  SET is_active = false
  WHERE expires_at < NOW() AND is_active = true;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Called by the owner to reset the 7-day expiry clock
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
-- STEP 8: ROW LEVEL SECURITY (RLS)
-- ────────────────────────────────────────────────────────────

-- Enable RLS
ALTER TABLE public.profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.items    ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.ai_logs  ENABLE ROW LEVEL SECURITY;


-- ── Profiles Policies ──────────────────────────────────────

-- Anyone can read all profiles (needed to display owner info on cards)
CREATE POLICY "profiles_public_read"
  ON public.profiles FOR SELECT
  USING (true);

-- A user can only insert their own profile
CREATE POLICY "profiles_self_insert"
  ON public.profiles FOR INSERT
  WITH CHECK (auth.uid() = id);

-- A user can only update their own profile
CREATE POLICY "profiles_self_update"
  ON public.profiles FOR UPDATE
  USING (auth.uid() = id)
  WITH CHECK (auth.uid() = id);


-- ── Items Policies ─────────────────────────────────────────

-- Public can read all active items only
CREATE POLICY "items_public_read"
  ON public.items FOR SELECT
  USING (is_active = true);

-- Only VERIFIED students can create items
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

-- Only the owner can update their item (e.g., mark as Sold/Returned)
CREATE POLICY "items_owner_update"
  ON public.items FOR UPDATE
  USING (auth.uid() = owner_id)
  WITH CHECK (auth.uid() = owner_id);

-- Only the owner can delete their item
CREATE POLICY "items_owner_delete"
  ON public.items FOR DELETE
  USING (auth.uid() = owner_id);


-- ── AI Logs Policies ───────────────────────────────────────

-- Users can only read their own AI conversation logs
CREATE POLICY "ai_logs_owner_read"
  ON public.ai_logs FOR SELECT
  USING (auth.uid() = user_id);

-- Authenticated users can insert their own logs
CREATE POLICY "ai_logs_auth_insert"
  ON public.ai_logs FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL AND auth.uid() = user_id);


-- ────────────────────────────────────────────────────────────
-- STEP 8: SAMPLE DATA
-- NOTE: profiles.id must match a real auth.users(id).
-- Sign up real users first via the app, then seed items here.
-- The block below is intentionally left empty for safety.
-- ────────────────────────────────────────────────────────────

DO $$
BEGIN
  -- Seed data removed: profiles.id must reference a real auth.users(id).
  -- Sign up via the app first, then insert items here using the real UUID.
END $$;
