CREATE TABLE IF NOT EXISTS `qbmdt_reports` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(160) NOT NULL,
  `narrative` TEXT NOT NULL,
  `status` ENUM('open','closed') NOT NULL DEFAULT 'open',
  `subject_citizenid` VARCHAR(64) DEFAULT NULL,
  `charge_code` VARCHAR(32) DEFAULT NULL,
  `author_citizenid` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mdt_reports_status_updated` (`status`,`updated_at`),
  KEY `idx_mdt_reports_subject` (`subject_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_cases` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `title` VARCHAR(160) NOT NULL,
  `summary` TEXT NOT NULL,
  `priority` ENUM('low','normal','high','critical') NOT NULL DEFAULT 'normal',
  `status` ENUM('open','investigating','closed') NOT NULL DEFAULT 'open',
  `lead_citizenid` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mdt_cases_status_updated` (`status`,`updated_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_case_reports` (
  `case_id` BIGINT UNSIGNED NOT NULL,
  `report_id` BIGINT UNSIGNED NOT NULL,
  PRIMARY KEY (`case_id`,`report_id`),
  KEY `idx_mdt_case_reports_report` (`report_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_warrants` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(64) NOT NULL,
  `reason` VARCHAR(1000) NOT NULL,
  `status` ENUM('active','served','revoked') NOT NULL DEFAULT 'active',
  `author_citizenid` VARCHAR(64) NOT NULL,
  `closed_by_citizenid` VARCHAR(64) DEFAULT NULL,
  `expires_at` DATETIME NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mdt_warrants_subject_status` (`citizenid`,`status`),
  KEY `idx_mdt_warrants_status_expiry` (`status`,`expires_at`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_bolos` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `subject_type` ENUM('person','vehicle') NOT NULL,
  `subject_identifier` VARCHAR(96) NOT NULL,
  `title` VARCHAR(160) NOT NULL,
  `description` VARCHAR(1500) NOT NULL,
  `status` ENUM('active','resolved') NOT NULL DEFAULT 'active',
  `author_citizenid` VARCHAR(64) NOT NULL,
  `expires_at` DATETIME DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mdt_bolos_status_updated` (`status`,`updated_at`),
  KEY `idx_mdt_bolos_subject` (`subject_type`,`subject_identifier`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_audit_log` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `actor_citizenid` VARCHAR(64) NOT NULL,
  `action` VARCHAR(64) NOT NULL,
  `target_type` VARCHAR(32) NOT NULL,
  `target_id` VARCHAR(96) NOT NULL,
  `details` VARCHAR(1000) DEFAULT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_mdt_audit_created` (`created_at`),
  KEY `idx_mdt_audit_actor` (`actor_citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
