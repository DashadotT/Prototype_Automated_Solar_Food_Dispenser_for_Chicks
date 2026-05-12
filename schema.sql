-- ============================================================
-- SolarFeed IoT — Professional Supabase Schema v2.0
-- Run this entire file in Supabase SQL Editor
-- ============================================================

-- ──────────────────────────────────────────────────────────
-- ENABLE UUID extension (if not already enabled)
-- ──────────────────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- ──────────────────────────────────────────────────────────
-- 1. SENSOR READINGS
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS sensor_readings (
  id              BIGSERIAL PRIMARY KEY,
  distance_cm     DECIMAL(6,2) NOT NULL CHECK (distance_cm >= 0),
  food_level      TEXT NOT NULL CHECK (food_level IN ('Full','Medium','Low','Empty','Unknown')),
  food_percentage INTEGER DEFAULT 0 CHECK (food_percentage BETWEEN 0 AND 100),
  created_at      TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  note            TEXT
);

-- Index for fast time-range queries
CREATE INDEX IF NOT EXISTS idx_sensor_readings_created_at
  ON sensor_readings (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_sensor_readings_food_level
  ON sensor_readings (food_level);

-- ──────────────────────────────────────────────────────────
-- 2. SERVO STATE (single-row table)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS servo_state (
  id         INTEGER PRIMARY KEY DEFAULT 1,
  state      TEXT NOT NULL DEFAULT 'Closed' CHECK (state IN ('Open','Closed')),
  angle      INTEGER DEFAULT 90 CHECK (angle BETWEEN 0 AND 180),
  updated_at TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

-- Ensure only one row exists
INSERT INTO servo_state (id, state, angle)
VALUES (1, 'Closed', 90)
ON CONFLICT (id) DO NOTHING;

-- Trigger: auto-update updated_at
CREATE OR REPLACE FUNCTION fn_update_timestamp()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

DROP TRIGGER IF EXISTS trg_servo_updated_at ON servo_state;
CREATE TRIGGER trg_servo_updated_at
  BEFORE UPDATE ON servo_state
  FOR EACH ROW EXECUTE FUNCTION fn_update_timestamp();

-- ──────────────────────────────────────────────────────────
-- 3. FEEDING SCHEDULES
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS feeding_schedules (
  id               BIGSERIAL PRIMARY KEY,
  feeding_time     TIME NOT NULL,
  label            TEXT DEFAULT 'Feeding',
  enabled          BOOLEAN DEFAULT TRUE NOT NULL,
  duration_seconds INTEGER DEFAULT 5 CHECK (duration_seconds BETWEEN 1 AND 60),
  created_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  updated_at       TIMESTAMPTZ DEFAULT NOW() NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_feeding_schedules_enabled
  ON feeding_schedules (enabled, feeding_time);

-- ──────────────────────────────────────────────────────────
-- 4. FEEDING LOGS
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS feeding_logs (
  id          BIGSERIAL PRIMARY KEY,
  type        TEXT NOT NULL CHECK (type IN ('manual','automatic','system','alert','error','wifi')),
  action      TEXT NOT NULL,
  servo_angle INTEGER,
  created_at  TIMESTAMPTZ DEFAULT NOW() NOT NULL,
  note        TEXT
);

CREATE INDEX IF NOT EXISTS idx_feeding_logs_created_at
  ON feeding_logs (created_at DESC);

CREATE INDEX IF NOT EXISTS idx_feeding_logs_type
  ON feeding_logs (type, created_at DESC);

-- ──────────────────────────────────────────────────────────
-- 5. SYSTEM SETTINGS (single-row table)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS system_settings (
  id                   INTEGER PRIMARY KEY DEFAULT 1,
  servo_open_angle     INTEGER DEFAULT 60  CHECK (servo_open_angle BETWEEN 0 AND 180),
  servo_closed_angle   INTEGER DEFAULT 90  CHECK (servo_closed_angle BETWEEN 0 AND 180),
  dispense_duration    INTEGER DEFAULT 5   CHECK (dispense_duration BETWEEN 1 AND 60),
  refill_threshold_cm  DECIMAL(5,2) DEFAULT 3.0,
  sensor_interval      INTEGER DEFAULT 5   CHECK (sensor_interval BETWEEN 1 AND 300),
  updated_at           TIMESTAMPTZ DEFAULT NOW()
);

-- Default settings row
INSERT INTO system_settings (id, servo_open_angle, servo_closed_angle, dispense_duration, refill_threshold_cm, sensor_interval)
VALUES (1, 60, 90, 5, 3.0, 5)
ON CONFLICT (id) DO NOTHING;

-- ──────────────────────────────────────────────────────────
-- 6. SYSTEM STATUS (single-row table)
-- ──────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS system_status (
  id              INTEGER PRIMARY KEY DEFAULT 1,
  esp32_online    BOOLEAN DEFAULT FALSE,
  wifi_status     TEXT DEFAULT 'unknown',
  last_seen       TIMESTAMPTZ DEFAULT NOW(),
  uptime_seconds  INTEGER DEFAULT 0,
  updated_at      TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO system_status (id)
VALUES (1)
ON CONFLICT (id) DO NOTHING;

-- ──────────────────────────────────────────────────────────
-- VIEWS
-- ──────────────────────────────────────────────────────────

-- Latest sensor reading
CREATE OR REPLACE VIEW v_latest_sensor AS
  SELECT * FROM sensor_readings
  ORDER BY created_at DESC
  LIMIT 1;

-- Daily feeding summary
CREATE OR REPLACE VIEW v_daily_summary AS
  SELECT
    DATE(created_at) AS day,
    COUNT(*) FILTER (WHERE type = 'manual')    AS manual_count,
    COUNT(*) FILTER (WHERE type = 'automatic') AS auto_count,
    COUNT(*) AS total_count
  FROM feeding_logs
  WHERE type IN ('manual','automatic')
  GROUP BY DATE(created_at)
  ORDER BY day DESC;

-- Today's low food alerts
CREATE OR REPLACE VIEW v_low_food_today AS
  SELECT COUNT(*) AS count
  FROM sensor_readings
  WHERE food_level IN ('Low','Empty')
    AND created_at >= CURRENT_DATE;

-- ──────────────────────────────────────────────────────────
-- ROW LEVEL SECURITY (RLS)
-- ──────────────────────────────────────────────────────────
ALTER TABLE sensor_readings  ENABLE ROW LEVEL SECURITY;
ALTER TABLE servo_state      ENABLE ROW LEVEL SECURITY;
ALTER TABLE feeding_schedules ENABLE ROW LEVEL SECURITY;
ALTER TABLE feeding_logs     ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_settings  ENABLE ROW LEVEL SECURITY;
ALTER TABLE system_status    ENABLE ROW LEVEL SECURITY;

-- Drop existing policies if re-running
DO $$ BEGIN
  DROP POLICY IF EXISTS "anon_all_sensor_readings" ON sensor_readings;
  DROP POLICY IF EXISTS "anon_all_servo_state" ON servo_state;
  DROP POLICY IF EXISTS "anon_all_feeding_schedules" ON feeding_schedules;
  DROP POLICY IF EXISTS "anon_all_feeding_logs" ON feeding_logs;
  DROP POLICY IF EXISTS "anon_all_system_settings" ON system_settings;
  DROP POLICY IF EXISTS "anon_all_system_status" ON system_status;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- Public access policies (ESP32 + dashboard use anon key)
-- ⚠️ For production: add authentication and restrict policies
CREATE POLICY "anon_all_sensor_readings"
  ON sensor_readings FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_servo_state"
  ON servo_state FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_feeding_schedules"
  ON feeding_schedules FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_feeding_logs"
  ON feeding_logs FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_system_settings"
  ON system_settings FOR ALL TO anon USING (true) WITH CHECK (true);

CREATE POLICY "anon_all_system_status"
  ON system_status FOR ALL TO anon USING (true) WITH CHECK (true);

-- ──────────────────────────────────────────────────────────
-- REALTIME
-- Enable realtime for all tables
-- ──────────────────────────────────────────────────────────
ALTER PUBLICATION supabase_realtime ADD TABLE sensor_readings;
ALTER PUBLICATION supabase_realtime ADD TABLE servo_state;
ALTER PUBLICATION supabase_realtime ADD TABLE feeding_schedules;
ALTER PUBLICATION supabase_realtime ADD TABLE feeding_logs;
ALTER PUBLICATION supabase_realtime ADD TABLE system_status;

-- ──────────────────────────────────────────────────────────
-- FUNCTION: cleanup old sensor readings (keep last 7 days)
-- ──────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION fn_cleanup_old_readings()
RETURNS void AS $$
BEGIN
  DELETE FROM sensor_readings
  WHERE created_at < NOW() - INTERVAL '7 days';

  DELETE FROM feeding_logs
  WHERE created_at < NOW() - INTERVAL '30 days';
END;
$$ LANGUAGE plpgsql;
