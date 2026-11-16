-- The companion's name, 2026-11-16.
--
-- The chat labels the assistant's lines with a fixed word. An older adult
-- calling it whatever feels familiar ("小安", "老伴", their late husband's
-- nickname) is a small thing that makes the appliance feel like theirs, and it
-- is a choice only they should make: the family phone cannot change it.
--
-- NULL means "the product default", so an empty value is stored as NULL rather
-- than as an empty string.
ALTER TABLE preferences ADD COLUMN assistant_name TEXT;
