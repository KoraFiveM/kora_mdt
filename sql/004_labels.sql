-- Unlinked report subjects / free-text charges and a readable BOLO subject label.
-- Retry-safe (ADD COLUMN IF NOT EXISTS) so kora_sql can apply it automatically.
ALTER TABLE `qbmdt_reports` ADD COLUMN IF NOT EXISTS `subject_text` VARCHAR(96) DEFAULT NULL AFTER `subject_citizenid`;
ALTER TABLE `qbmdt_reports` ADD COLUMN IF NOT EXISTS `charge_text` VARCHAR(128) DEFAULT NULL AFTER `charge_code`;
ALTER TABLE `qbmdt_bolos` ADD COLUMN IF NOT EXISTS `subject_label` VARCHAR(160) DEFAULT NULL AFTER `subject_identifier`;
