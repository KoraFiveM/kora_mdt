CREATE TABLE IF NOT EXISTS `qbmdt_licences` (
  `citizenid` VARCHAR(64) NOT NULL,
  `licence_type` VARCHAR(32) NOT NULL,
  `licence_number` VARCHAR(64) NOT NULL,
  `issued_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`citizenid`,`licence_type`),
  UNIQUE KEY `uq_mdt_licence_number` (`licence_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_firearms` (
  `serial` VARCHAR(96) NOT NULL,
  `weapon_name` VARCHAR(96) NOT NULL,
  `owner_citizenid` VARCHAR(64) NOT NULL,
  `licence_number` VARCHAR(64) NOT NULL,
  `shop_id` VARCHAR(64) NOT NULL,
  `purchased_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`serial`),
  KEY `idx_mdt_firearms_owner` (`owner_citizenid`),
  KEY `idx_mdt_firearms_licence` (`licence_number`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_charges` (
  `code` VARCHAR(32) NOT NULL,
  `label` VARCHAR(128) NOT NULL,
  `fine` INT UNSIGNED NOT NULL,
  `active` TINYINT(1) NOT NULL DEFAULT 1,
  PRIMARY KEY (`code`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_criminal_records` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(64) NOT NULL,
  `charge_code` VARCHAR(32) NOT NULL,
  `notes` VARCHAR(1000) DEFAULT NULL,
  `author_citizenid` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_mdt_criminal_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;

CREATE TABLE IF NOT EXISTS `qbmdt_medical_records` (
  `id` BIGINT UNSIGNED NOT NULL AUTO_INCREMENT,
  `citizenid` VARCHAR(64) NOT NULL,
  `notes` VARCHAR(1000) NOT NULL,
  `author_citizenid` VARCHAR(64) NOT NULL,
  `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`), KEY `idx_mdt_medical_citizen` (`citizenid`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
