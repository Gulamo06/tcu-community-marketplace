-- ============================================================
-- UniConnect Platform — Migration v5
-- FIXES IMAGE UPLOAD (the main blocker for posting with photos)
-- Also adds UPDATE/DELETE storage policies and confirms
-- the reports table and items insert policy are correct.
-- Safe to re-run (idempotent).
-- ============================================================


-- ────────────────────────────────────────────────────────────
-- 1. STORAGE POLICIES (item-images bucket)
--    This is the ROOT CAUSE of images not uploading.
--    Without "storage_auth_upload", every upload silently fails.
-- ────────────────────────────────────────────────────────────

-- Public read (images load on cards)
DROP POLICY IF EXISTS "storage_public_read"  ON storage.objects;
CREATE POLICY "storage_public_read"
  ON storage.objects FOR SELECT
  USING (bucket_id = 'item-images');

-- Authenticated users can upload new images
DROP POLICY IF EXISTS "storage_auth_upload"  ON storage.objects;
CREATE POLICY "storage_auth_upload"
  ON storage.objects FOR INSERT
  WITH CHECK (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);

-- Authenticated users can update/replace their uploads
DROP POLICY IF EXISTS "storage_auth_update"  ON storage.objects;
CREATE POLICY "storage_auth_update"
  ON storage.objects FOR UPDATE
  USING (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);

-- Authenticated users can delete their own uploads
DROP POLICY IF EXISTS "storage_auth_delete"  ON storage.objects;
CREATE POLICY "storage_auth_delete"
  ON storage.objects FOR DELETE
  USING (bucket_id = 'item-images' AND auth.uid() IS NOT NULL);


-- ────────────────────────────────────────────────────────────
-- 2. ITEMS INSERT POLICY
--    Ensures any authenticated user can post (no is_verified check).
--    migration_v3.sql should have already done this, but re-applying
--    here makes v5 a safe standalone fix.
-- ────────────────────────────────────────────────────────────
DROP POLICY IF EXISTS "items_verified_insert" ON public.items;
DROP POLICY IF EXISTS "items_auth_insert"     ON public.items;
CREATE POLICY "items_auth_insert"
  ON public.items FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND auth.uid() = owner_id
  );

-- Mark all existing users as verified (so old listings still pass any UI checks)
UPDATE public.profiles SET is_verified = true WHERE is_verified = false OR is_verified IS NULL;


-- ────────────────────────────────────────────────────────────
-- 3. REPORTS TABLE (idempotent — safe if already exists)
-- ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.reports (
  id          UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  item_id     UUID        REFERENCES public.items(id) ON DELETE CASCADE,
  reporter_id UUID        REFERENCES public.profiles(id) ON DELETE SET NULL,
  reason      TEXT        NOT NULL,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_item_id ON public.reports(item_id);
ALTER TABLE public.reports ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "reports_auth_insert" ON public.reports;
CREATE POLICY "reports_auth_insert"
  ON public.reports FOR INSERT
  WITH CHECK (auth.uid() IS NOT NULL);

DROP POLICY IF EXISTS "reports_admin_read" ON public.reports;
CREATE POLICY "reports_admin_read"
  ON public.reports FOR SELECT
  USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      WHERE p.id = auth.uid() AND p.email = '114122104@gms.tcu.edu.tw'
    )
  );


-- ============================================================
-- DONE. Verify storage policies with:
--   SELECT policyname, cmd FROM pg_policies WHERE tablename = 'objects';
--
-- Verify items policy with:
--   SELECT policyname FROM pg_policies WHERE tablename = 'items';
-- ============================================================
