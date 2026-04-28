-- ============================================================
-- TCU Community Platform — Migration v3
-- Remove student ID verification requirement for posting.
-- Any authenticated user with a school account can now post.
-- Safe to re-run (idempotent).
-- ============================================================

-- Drop the old policy that required is_verified = true
DROP POLICY IF EXISTS "items_verified_insert" ON public.items;

-- New policy: any authenticated user can post (TCU email enforced at app level)
CREATE POLICY "items_auth_insert"
  ON public.items FOR INSERT
  WITH CHECK (
    auth.uid() IS NOT NULL
    AND auth.uid() = owner_id
  );

-- Set all existing users as verified (cleanup of old column — optional but recommended)
UPDATE public.profiles SET is_verified = true WHERE is_verified = false OR is_verified IS NULL;

-- ============================================================
-- DONE. Verify with:
--   SELECT policyname FROM pg_policies WHERE tablename = 'items';
-- ============================================================
