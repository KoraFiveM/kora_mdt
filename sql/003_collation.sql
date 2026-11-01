-- MANUAL migration (not registered in server/migrate.lua; kora_sql rejects
-- non retry-safe DDL). Run by hand off-peak after a backup if wanted.
-- Align every qbmdt_* table with the collation used by kora_core (players,
-- player_vehicles, bank tables): utf8mb4_unicode_ci. Tables created by 001/002
-- before they declared a collation inherited the server default
-- (utf8mb4_general_ci), which breaks joins against players with
-- "Illegal mix of collations". CONVERT TO is idempotent: re-running on a table
-- that is already utf8mb4_unicode_ci is a no-op rebuild. Indexes are rebuilt.
ALTER TABLE `qbmdt_licences` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_firearms` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_charges` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_criminal_records` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_medical_records` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_reports` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_cases` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_case_reports` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_warrants` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_bolos` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
ALTER TABLE `qbmdt_audit_log` CONVERT TO CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
