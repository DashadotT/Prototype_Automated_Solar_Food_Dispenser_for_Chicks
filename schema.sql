-- ============================================================
-- SCHEMA for Solar-Powered Food Dispenser IoT Dashboard
-- ============================================================

-- 1. Create table for sensor readings (history log)
CREATE TABLE IF NOT EXISTS sensor_readings (
  id BIGSERIAL PRIMARY KEY,
  distance_cm DECIMAL(6,2) NOT NULL,
  food_level TEXT NOT NULL,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  note TEXT  -- optional, for manual action notes
);

-- 2. Create table for servo/gate state (single row)
CREATE TABLE IF NOT EXISTS servo_state (
  id INTEGER PRIMARY KEY DEFAULT 1,
  state TEXT NOT NULL CHECK (state IN ('Open', 'Closed')),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- 3. Insert initial servo state (Closed by default)
INSERT INTO servo_state (id, state) 
VALUES (1, 'Closed')
ON CONFLICT (id) DO NOTHING;

-- 4. Enable Row Level Security (RLS)
ALTER TABLE sensor_readings ENABLE ROW LEVEL SECURITY;
ALTER TABLE servo_state ENABLE ROW LEVEL SECURITY;

-- 5. Create policy for anonymous/public access (for ESP32 + web dashboard)
-- WARNING: For production, restrict with proper authentication
CREATE POLICY "Enable all for anon key" ON sensor_readings
  FOR ALL USING (true);

CREATE POLICY "Enable all for anon key" ON servo_state
  FOR ALL USING (true);

-- 6. Create index for faster history queries
CREATE INDEX IF NOT EXISTS idx_sensor_readings_created_at 
ON sensor_readings(created_at DESC);

-- 7. (Optional) Create a view for latest reading
CREATE OR REPLACE VIEW latest_sensor_reading AS
SELECT * FROM sensor_readings 
ORDER BY created_at DESC 
LIMIT 1;

-- 8. (Optional) Add a trigger to auto-update servo_state.updated_at
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER update_servo_state_updated_at
BEFORE UPDATE ON servo_state
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();