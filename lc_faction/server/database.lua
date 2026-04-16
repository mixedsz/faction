-- Database Setup: creates all required tables on resource start

CreateThread(function()
    -- Factions table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_factions` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `name` VARCHAR(64) NOT NULL UNIQUE,
            `label` VARCHAR(128) NOT NULL,
            `type` VARCHAR(32) NOT NULL DEFAULT 'gang',
            `reputation` INT NOT NULL DEFAULT 0,
            `active_wars` INT NOT NULL DEFAULT 0,
            `max_wars` INT NOT NULL DEFAULT 2,
            `gun_drop_eligible` TINYINT(1) NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    -- Members table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_members` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT NOT NULL,
            `identifier` VARCHAR(64) NOT NULL,
            `player_name` VARCHAR(128) DEFAULT NULL,
            `rank` VARCHAR(32) NOT NULL DEFAULT 'runner',
            `warnings` INT NOT NULL DEFAULT 0,
            `last_warning_reason` TEXT DEFAULT NULL,
            `cks_involved` INT NOT NULL DEFAULT 0,
            `reputation_contribution` INT NOT NULL DEFAULT 0,
            `last_active` INT NOT NULL DEFAULT 0,
            `joined_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY `uq_member` (`faction_id`, `identifier`),
            KEY `idx_identifier` (`identifier`)
        )
    ]])

    -- Territory table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_territory` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT NOT NULL,
            `name` VARCHAR(128) NOT NULL,
            `type` VARCHAR(32) NOT NULL DEFAULT 'turf',
            `x` FLOAT NOT NULL,
            `y` FLOAT NOT NULL,
            `z` FLOAT NOT NULL,
            `radius` FLOAT NOT NULL DEFAULT 50.0,
            `stash_id` VARCHAR(128) DEFAULT NULL,
            `active_members` INT NOT NULL DEFAULT 0,
            `sell_time` INT NOT NULL DEFAULT 0,
            `claimed_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    -- Conflicts table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_conflicts` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction1_id` INT NOT NULL,
            `faction2_id` INT NOT NULL,
            `type` VARCHAR(32) NOT NULL DEFAULT 'war',
            `status` VARCHAR(32) NOT NULL DEFAULT 'active',
            `reason` TEXT DEFAULT NULL,
            `started_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `ended_at` TIMESTAMP NULL DEFAULT NULL
        )
    ]])

    -- Weapons table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_weapons` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT NOT NULL,
            `weapon_name` VARCHAR(128) NOT NULL,
            `serial_number` VARCHAR(128) NOT NULL,
            `weapon_hash` VARCHAR(64) DEFAULT NULL,
            `holder_identifier` VARCHAR(64) DEFAULT NULL,
            `holder_name` VARCHAR(128) DEFAULT NULL,
            `registered_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY `uq_serial` (`serial_number`)
        )
    ]])

    -- Weapon usage log
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_weapon_logs` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT DEFAULT NULL,
            `member_identifier` VARCHAR(64) NOT NULL,
            `weapon_hash` VARCHAR(64) NOT NULL,
            `is_altercation` TINYINT(1) NOT NULL DEFAULT 0,
            `is_violation` TINYINT(1) NOT NULL DEFAULT 0,
            `x` FLOAT DEFAULT NULL,
            `y` FLOAT DEFAULT NULL,
            `z` FLOAT DEFAULT NULL,
            `logged_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    -- Violations table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_violations` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT NOT NULL,
            `member_identifier` VARCHAR(64) DEFAULT NULL,
            `type` VARCHAR(64) NOT NULL,
            `details` TEXT DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
        )
    ]])

    -- Cooldowns table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_cooldowns` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT NOT NULL,
            `type` VARCHAR(64) NOT NULL,
            `expires_at` TIMESTAMP NOT NULL,
            `reason` TEXT DEFAULT NULL,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            UNIQUE KEY `uq_cooldown` (`faction_id`, `type`)
        )
    ]])

    -- CK Requests table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_ck_requests` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `requesting_faction_id` INT NOT NULL,
            `requester_identifier` VARCHAR(64) NOT NULL,
            `target_identifier` VARCHAR(64) NOT NULL,
            `target_name` VARCHAR(128) NOT NULL,
            `reason` TEXT DEFAULT NULL,
            `status` VARCHAR(32) NOT NULL DEFAULT 'pending',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])

    -- Reports table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_reports` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT NOT NULL,
            `target_faction_id` INT DEFAULT NULL,
            `reporter_identifier` VARCHAR(64) NOT NULL,
            `reporter_name` VARCHAR(128) DEFAULT NULL,
            `report_type` VARCHAR(64) NOT NULL,
            `details` TEXT NOT NULL,
            `status` VARCHAR(32) NOT NULL DEFAULT 'pending',
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])

    -- Rules table
    MySQL.query([[
        CREATE TABLE IF NOT EXISTS `faction_rules` (
            `id` INT AUTO_INCREMENT PRIMARY KEY,
            `faction_id` INT DEFAULT NULL,
            `title` VARCHAR(256) NOT NULL,
            `content` TEXT NOT NULL,
            `is_global` TINYINT(1) NOT NULL DEFAULT 0,
            `order` INT NOT NULL DEFAULT 0,
            `created_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            `updated_at` TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP
        )
    ]])

    print('^2[lc_faction] Database tables initialised.^7')
end)
