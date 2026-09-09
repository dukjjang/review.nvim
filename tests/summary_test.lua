vim.opt.rtp:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path
local h = require("helpers")
local review = require("review")
local api = vim.api
review.setup({ auto_advance = false })
vim.o.columns, vim.o.lines = 120, 40
vim.env.XDG_DATA_HOME = vim.fn.tempname()
local root = h.project()
local function summary()
  local found
  for _, win in ipairs(api.nvim_list_wins()) do
    if vim.bo[api.nvim_win_get_buf(win)].filetype == "review_summary" then
      assert(not found, "Only one summary may be visible")
      found = win
    end
  end
  return found
end
local function expect(text)
  local win = assert(summary(), "Review summary must be visible")
  h.equal(api.nvim_buf_get_lines(api.nvim_win_get_buf(win), 0, -1, false), { text }, "Summary counts must reflect source decisions")
  local opts = api.nvim_win_get_config(win)
  h.equal(opts.relative, "editor", "Summary must use editor coordinates")
  h.equal(opts.row, 0, "Summary must stay at the top")
  h.equal(opts.col + opts.width, vim.o.columns, "Summary must align to the right")
  h.equal(opts.focusable, false, "Summary must not take editing focus")
end
local ok, err = xpcall(function()
  vim.cmd("cd " .. vim.fn.fnameescape(root))
  assert(not summary(), "Summary must be absent outside review mode")
  review.open({ root = root })
  local editor, buf = api.nvim_get_current_win(), api.nvim_get_current_buf()
  expect(" REVIEW  OK 1 | PENDING 2 | REJECT 0 ")
  review.mark("OK")
  expect(" REVIEW  OK 2 | PENDING 1 | REJECT 0 ")
  review.mark("REJECT")
  expect(" REVIEW  OK 1 | PENDING 1 | REJECT 1 ")
  review.mark("PENDING")
  expect(" REVIEW  OK 1 | PENDING 2 | REJECT 0 ")
  review.mark("OK")
  api.nvim_exec_autocmds("TextChanged", { buffer = buf })
  expect(" REVIEW  OK 2 | PENDING 1 | REJECT 0 ")
  h.equal(api.nvim_get_current_win(), editor, "Updates must preserve editing focus")
  vim.o.columns = 80
  api.nvim_exec_autocmds("VimResized", {})
  expect(" REVIEW  OK 2 | PENDING 1 | REJECT 0 ")
  review.close()
  assert(not summary(), "Pause must hide the summary")
  review.toggle()
  expect(" REVIEW  OK 2 | PENDING 1 | REJECT 0 ")
  vim.cmd("tabnew")
  expect(" REVIEW  OK 2 | PENDING 1 | REJECT 0 ")
  review.stop()
  assert(not summary(), "Stop must close the summary")
  vim.cmd("tabprevious")
  assert(not summary(), "No summary may remain in the previous tab")
  api.nvim_buf_set_lines(buf, 0, -1, false, { "-- no review points" })
  review.open({ buffer = true })
  expect(" REVIEW  OK 2 | PENDING 0 | REJECT 0  | 위치 재확인 2")
  review.stop()
end, debug.traceback)
vim.fn.delete(root, "rf")
vim.fn.delete(vim.env.XDG_DATA_HOME, "rf")
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
print("PASS: summary counts, direct edits, focus, resize, pause/resume, tabs, stop and empty scope")
vim.cmd("qa!")
