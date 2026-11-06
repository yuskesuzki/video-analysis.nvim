local Timer = require("video-analysis.timer")
local Buffer = require("video-analysis.buffer")

local uv = vim.uv or vim.loop

local M = {}

M.defaults = {
  chapter_format = "%s - %s: %s",
  keymaps = {
    start = "S",
    next = "<Space>",
    pause = "P",
    change_time = "C",
    stop = "E",
  },
  status = {
    icon_play = "▶",
    icon_pause = "⏸",
    icon_stop = "⏹",
    format = "%s %s [ch.%d]",
  },
}

M.config = vim.deepcopy(M.defaults)

-- Active sessions per buffer
local sessions = {}

function M.setup(opts)
  M.config = vim.tbl_deep_extend("force", M.config, opts or {})
end

local function notify(msg, level)
  vim.notify(msg, level or vim.log.levels.INFO, { title = "Video Analysis" })
end

local function get_session(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  return sessions[bufnr]
end

local function start_status_ticker(session)
  if session.status_ticker then
    return
  end
  local ticker = uv.new_timer()
  ticker:start(
    0,
    500,
    vim.schedule_wrap(function()
      if session and session.timer and session.timer.is_running then
        vim.cmd("redrawstatus")
      end
    end)
  )
  session.status_ticker = ticker
end

local function stop_status_ticker(session)
  if session.status_ticker then
    session.status_ticker:stop()
    session.status_ticker:close()
    session.status_ticker = nil
  end
  pcall(vim.cmd, "redrawstatus")
end

-- Public API for statusline / lualine
function M.is_active(bufnr)
  return get_session(bufnr) ~= nil
end

function M.status(bufnr)
  local session = get_session(bufnr)
  if not session then
    return ""
  end

  local st_cfg = M.config.status
  if not session.timer.is_running then
    return string.format("%s 0:00:00 [S: Start]", st_cfg.icon_stop)
  end

  local curr_sec = session.timer:get_current_seconds()
  local time_str = Timer.format_time(curr_sec)
  local idx = session.timer.chapter_index

  if session.timer.is_paused then
    return string.format("%s %s [PAUSED ch.%d]", st_cfg.icon_pause, time_str, idx)
  end

  return string.format(st_cfg.format, st_cfg.icon_play, time_str, idx)
end

function M.on_start(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  session.timer:start()
  start_status_ticker(session)
  notify("Timer started! Press <Space> for chapter, 'P' to pause, 'C' to set time, 'E' to finish.")
end

function M.on_next(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  if not session.timer.is_running then
    notify("Timer is not started yet. Press 'S' to start.", vim.log.levels.WARN)
    return
  end

  -- Snapshot timestamp at the exact moment Space is pressed
  local start_str, end_str, idx = session.timer:next_chapter()
  if not start_str then
    return
  end

  local default_title = string.format("chapter %d", idx)

  vim.ui.input({
    prompt = string.format("Note for chapter %d (%s - %s): ", idx, start_str, end_str),
    default = default_title,
  }, function(input)
    local title = input
    -- If user pressed <Esc> or entered empty text, fall back to default chapter name
    if not title or vim.trim(title) == "" then
      title = default_title
    end

    local line = string.format(M.config.chapter_format, start_str, end_str, title)
    Buffer.insert_chapter_line(bufnr, line)
    notify(string.format("Recorded: %s", line))
  end)
end

function M.on_pause(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  if not session.timer.is_running then
    notify("Timer is not started yet.", vim.log.levels.WARN)
    return
  end

  local is_paused = session.timer:toggle_pause()
  local curr_str = Timer.format_time(session.timer:get_current_seconds())
  if is_paused then
    notify(string.format("Paused at %s (press 'P' again to resume)", curr_str))
  else
    notify(string.format("Resumed at %s", curr_str))
  end
end

function M.on_change_time(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  if not session.timer.is_running then
    notify("Timer is not started yet. Press 'S' to start.", vim.log.levels.WARN)
    return
  end

  -- Automatically pause while waiting for user input
  local was_paused = session.timer.is_paused
  session.timer:pause()

  local current_str = Timer.format_time(session.timer:get_current_seconds())

  vim.ui.input({
    prompt = "Set video time (H:MM:SS / M:SS / seconds): ",
    default = current_str,
  }, function(input)
    -- User cancelled (e.g. <Esc>)
    if not input then
      if not was_paused then
        session.timer:resume()
      end
      notify("Cancelled time change.", vim.log.levels.INFO)
      return
    end

    local new_sec = Timer.parse_time(input)
    if not new_sec then
      if not was_paused then
        session.timer:resume()
      end
      notify(string.format("Invalid time format: '%s'. Kept at %s", input, current_str), vim.log.levels.ERROR)
      return
    end

    -- Automatically resume counting from new time
    session.timer:set_time(new_sec, true)
    notify(string.format("Time set to %s. Resumed counting.", Timer.format_time(new_sec)))
  end)
end

function M.on_finish(bufnr)
  local session = get_session(bufnr)
  if not session then
    return
  end

  if session.timer.is_running then
    local start_str, end_str, idx = session.timer:finish()
    local default_title = string.format("chapter %d", idx)

    vim.ui.input({
      prompt = string.format("Note for final chapter %d (%s - %s): ", idx, start_str, end_str),
      default = default_title,
    }, function(input)
      local title = input
      if not title or vim.trim(title) == "" then
        title = default_title
      end

      local line = string.format(M.config.chapter_format, start_str, end_str, title)
      Buffer.insert_chapter_line(bufnr, line)
      notify(string.format("Finished! Recorded final chapter: %s", line))
      M.stop_mode(bufnr)
    end)
  else
    notify("Finished (timer was not running).")
    M.stop_mode(bufnr)
  end
end

function M.start_mode(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()

  if sessions[bufnr] then
    notify("Video analysis mode is already active in this buffer.", vim.log.levels.WARN)
    return
  end

  local timer = Timer.new()
  sessions[bufnr] = {
    timer = timer,
  }

  local keys = M.config.keymaps
  Buffer.setup_keymaps(bufnr, {
    [keys.start] = function()
      M.on_start(bufnr)
    end,
    [keys.next] = function()
      M.on_next(bufnr)
    end,
    [keys.pause] = function()
      M.on_pause(bufnr)
    end,
    [keys.change_time] = function()
      M.on_change_time(bufnr)
    end,
    [keys.stop] = function()
      M.on_finish(bufnr)
    end,
  })

  notify("Mode activated! Press 'S' to start timer, or 'E' to exit.")
  pcall(vim.cmd, "redrawstatus")
end

function M.stop_mode(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local session = sessions[bufnr]
  if not session then
    return
  end

  stop_status_ticker(session)
  session.timer:reset()
  Buffer.clear_keymaps(bufnr)
  sessions[bufnr] = nil
  pcall(vim.cmd, "redrawstatus")
end

return M
