-- ============================================================
-- TCU Community Platform — Migration v4
-- Adds reports table so users can flag offensive listings.
-- Safe to re-run (idempotent).
-- ============================================================

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
-- DONE. Verify with:
--   SELECT * FROM public.reports ORDER BY created_at DESC;
-- ============================================================
