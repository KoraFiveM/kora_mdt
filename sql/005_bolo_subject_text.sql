-- The BOLO subject exactly as the officer typed it. subject_identifier stays the lookup
-- key (linked citizen ID, plate or the free text) and is never shown as the subject.
-- Retry-safe (ADD COLUMN IF NOT EXISTS) so kora_sql can apply it automatically.
ALTER TABLE `qbmdt_bolos` ADD COLUMN IF NOT EXISTS `subject_text` VARCHAR(96) DEFAULT NULL AFTER `subject_identifier`;
