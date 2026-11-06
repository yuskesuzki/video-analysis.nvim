local M = {}

-- format seconds into H:MM:SS
function M.format_time(seconds)
  if not seconds or seconds < 0 then
    seconds = 0
  end
  local sec = math.floor(seconds + 0.5)
  local h = math.floor(sec / 3600)
  local m = math.floor((sec % 3600) / 60)
  local s = math.floor(sec % 60)
  return string.format("%d:%02d:%02d", h, m, s)
end

-- parse time string to seconds
-- Supports:
--   "H:MM:SS" (e.g. "0:15:30", "1:02:00")
--   "M:SS"    (e.g. "15:30", "5:00")
--   "seconds" (e.g. "900", "45")
function M.parse_time(str)
  if not str then
    return nil
  end
  local s = vim.trim(str)
  if s == "" then
    return nil
  end

  -- H:MM:SS
  local h, m, sec = s:match("^(%d+):(%d+):(%d+)$")
  if h and m and sec then
    local h_n, m_n, s_n = tonumber(h), tonumber(m), tonumber(sec)
    if m_n < 60 and s_n < 60 then
      return h_n * 3600 + m_n * 60 + s_n
    end
  end

  -- M:SS
  local m2, sec2 = s:match("^(%d+):(%d+)$")
  if m2 and sec2 then
    local m_n, s_n = tonumber(m2), tonumber(sec2)
    if s_n < 60 then
      return m_n * 60 + s_n
    end
  end

  -- pure seconds
  local num = tonumber(s)
  if num and num >= 0 then
    return math.floor(num)
  end

  return nil
end

local uv = vim.uv or vim.loop

local Timer = {}
Timer.__index = Timer

function M.new()
  local self = setmetatable({}, Timer)
  self:reset()
  return self
end

function Timer:reset()
  self.is_running = false
  self.is_paused = false
  self.accumulated_seconds = 0
  self.last_tick_ms = nil
  self.chapter_start_sec = 0
  self.chapter_index = 1
end

function Timer:start()
  self.is_running = true
  self.is_paused = false
  self.accumulated_seconds = 0
  self.last_tick_ms = uv.now()
  self.chapter_start_sec = 0
  self.chapter_index = 1
end

function Timer:get_current_seconds()
  if not self.is_running then
    return self.accumulated_seconds
  end

  if self.is_paused then
    return self.accumulated_seconds
  end

  local now = uv.now()
  local elapsed = (now - self.last_tick_ms) / 1000.0
  return self.accumulated_seconds + elapsed
end

function Timer:pause()
  if not self.is_running or self.is_paused then
    return
  end
  self.accumulated_seconds = self:get_current_seconds()
  self.is_paused = true
  self.last_tick_ms = nil
end

function Timer:resume()
  if not self.is_running or not self.is_paused then
    return
  end
  self.is_paused = false
  self.last_tick_ms = uv.now()
end

function Timer:toggle_pause()
  if not self.is_running then
    return nil
  end
  if self.is_paused then
    self:resume()
    return false -- now playing
  else
    self:pause()
    return true -- now paused
  end
end

-- Jump/set current video time
function Timer:set_time(new_seconds, resume_immediately)
  if new_seconds < 0 then
    new_seconds = 0
  end
  self.accumulated_seconds = new_seconds
  self.chapter_start_sec = new_seconds
  if resume_immediately then
    self.is_paused = false
    self.last_tick_ms = uv.now()
  else
    self.is_paused = true
    self.last_tick_ms = nil
  end
end

-- Next chapter record
-- Returns: start_str, end_str, chapter_index
function Timer:next_chapter()
  if not self.is_running then
    return nil, nil, nil
  end

  local curr_sec = self:get_current_seconds()
  local start_str = M.format_time(self.chapter_start_sec)
  local end_str = M.format_time(curr_sec)
  local idx = self.chapter_index

  -- Advance chapter start time and index
  self.chapter_start_sec = curr_sec
  self.chapter_index = self.chapter_index + 1

  return start_str, end_str, idx
end

-- Finish and return last chapter
function Timer:finish()
  if not self.is_running then
    return nil, nil, nil
  end

  local curr_sec = self:get_current_seconds()
  local start_str = M.format_time(self.chapter_start_sec)
  local end_str = M.format_time(curr_sec)
  local idx = self.chapter_index

  self.is_running = false
  self.is_paused = false
  return start_str, end_str, idx
end

return M
