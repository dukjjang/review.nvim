vim.opt.rtp:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path
local h = require("helpers")
local review = require("review")
local api = vim.api
review.setup()
vim.env.XDG_DATA_HOME = vim.fn.tempname()
local root = h.large_project(120)
local reads = 0
api.nvim_create_autocmd("BufReadPost", {
  pattern = root .. "/*.ts",
  callback = function() reads = reads + 1 end,
})

local function loaded_files()
  local count = 0
  for _, buf in ipairs(api.nvim_list_bufs()) do
    if api.nvim_buf_is_loaded(buf) and api.nvim_buf_get_name(buf):sub(1, #root + 1) == root .. "/" then
      count = count + 1
    end
  end
  return count
end

local ok, err = xpcall(function()
  review.open({ root = root })
  h.equal(loaded_files(), 1, "Opening 120 review points should load only the selected source file")
  h.equal(reads, 1, "Scanning must not trigger other files' read hooks")
  h.equal(#h.editor_windows(), 1, "Scanning must not create a side panel")
  review.next(1)
  h.equal(loaded_files(), 2, "Navigation should load just the next file")
  h.equal(reads, 2, "Navigation should run normal file hooks once for its target")
  review.next(-1)
  review.next(-1)
  review.setup({ auto_advance = false })
  review.mark("REJECT")
  h.equal(loaded_files(), 3, "Decisions should load only the selected unopened file")
  local last = vim.fn.bufnr(root .. "/120.ts")
  h.equal(api.nvim_buf_get_lines(last, 0, 1, false)[1], "const value = 120;", "Decision must leave source unchanged")
  h.equal(vim.fn.readfile(root .. "/120.ts")[1], "const value = 120;", "Decision must not alter source on disk")
  review.open({ root = root })
  h.equal(loaded_files(), 3, "Rescan should not load more files")
  review.stop()
end, debug.traceback)
vim.fn.delete(root, "rf")
vim.fn.delete(vim.env.XDG_DATA_HOME, "rf")
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
print("PASS: 120-file lazy scan, navigation, source decision and unsaved rescan")
vim.cmd("qa!")
