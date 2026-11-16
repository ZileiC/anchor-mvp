-- The voice the senior hears, 2026-11-16.
--
-- Two voices exist on the speech provider (a female and a male one), and which
-- one sounds right is a matter of taste the older adult is entitled to. Storing
-- the *gender* rather than the provider's voice id keeps the choice meaningful if
-- the provider or the fallback voice changes underneath it.
--
-- NULL means the product default (female), so existing profiles need no backfill.
ALTER TABLE preferences ADD COLUMN voice_gender TEXT;
