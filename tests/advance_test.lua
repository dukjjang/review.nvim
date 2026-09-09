vim.opt.rtp:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path
vim.env.XDG_DATA_HOME = vim.fn.tempname()
vim.g.mapleader = " "
local h, review, store = require("helpers"), require("review"), require("review.store")
local api = vim.api
local root = h.project()
local ok, err = xpcall(function()
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  vim.fn.writefile({ "local first = 1", "local second = 2", "local third = 3" }, root .. "/a.lua")
  local data, version = store.load(root)
  data.items = {}
  for row, name in ipairs({ "first", "second", "third" }) do
    data.items[row] = { id = name, path = "a.lua", row = row, anchor = { "local " .. name .. " = " .. row }, title = name, status = "PENDING" }
  end
  store.save(root, data, version)
  review.setup({ auto_advance = true })
  vim.cmd.edit(root .. "/a.lua")
  h.press(" rv")
  h.equal(api.nvim_win_get_cursor(0)[1], 1, "Start at first pending")
  h.press(" ro")
  h.equal(api.nvim_win_get_cursor(0)[1], 2, "OK must advance to second review without skipping it")
  h.press(" rx")
  h.equal(api.nvim_win_get_cursor(0)[1], 3, "REJECT must advance to third review")
  h.press(" ro")
  h.equal(api.nvim_win_get_cursor(0)[1], 3, "Stay when no pending remains")
  assert(not vim.bo.modified, "Decisions must not modify source")
  review.stop()
end, debug.traceback)
vim.fn.delete(root, "rf")
vim.fn.delete(vim.env.XDG_DATA_HOME, "rf")
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
print("PASS: sequential OK/REJECT advancement without skipping after sorting")
vim.cmd("qa!")
