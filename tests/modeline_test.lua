vim.opt.rtp:prepend(vim.fn.getcwd())
package.path = vim.fn.getcwd() .. "/tests/?.lua;" .. package.path
local h = require("helpers")
local review = require("review")
review.setup()
vim.env.XDG_DATA_HOME = vim.fn.tempname()
local root = h.modeline_project()
require("review.store").save(root, {version=1,root=root,items={{id="url",path="url.lua",row=2,anchor={"local url = 'https://example.test'"},title="URL handling",status="PENDING"}}}, nil)
vim.o.modeline = true
vim.o.modelines = 5

local ok, err = xpcall(function()
  review.open({ root = root })
  h.equal(vim.api.nvim_buf_get_name(0), root .. "/url.lua", "Malformed modeline should not prevent opening a review")
  h.equal(vim.o.modelines, 5, "Scanning should restore the user's modeline scan count")
  h.equal(vim.bo.modeline, true, "Scanning should preserve the buffer's modeline setting")
  h.equal(vim.bo.modified, false, "Loading should not modify the source")
  review.mark("OK")
  h.equal(require("review.store").load(root).items[1].status, "OK", "Decision must persist outside the source")
  assert(not vim.bo.modified)
  review.stop()
end, debug.traceback)

vim.fn.delete(root, "rf")
vim.fn.delete(vim.env.XDG_DATA_HOME, "rf")
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
print("PASS: malformed modeline review and option preservation")
vim.cmd("qa!")
