if vim.g.loaded_video_analysis == 1 then
  return
end
vim.g.loaded_video_analysis = 1

local va = require("video-analysis")

vim.api.nvim_create_user_command("VideoAnalysis", function()
  va.start_mode(0)
end, {
  desc = "Start Video Analysis mode in current buffer",
})

vim.api.nvim_create_user_command("VideoAnalysisStart", function()
  va.start_mode(0)
end, {
  desc = "Start Video Analysis mode in current buffer",
})

vim.api.nvim_create_user_command("VideoAnalysisStop", function()
  va.stop_mode(0)
end, {
  desc = "Stop Video Analysis mode in current buffer",
})
