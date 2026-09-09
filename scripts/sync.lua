-- nvim --headless -u NONE -i NONE -l /path/to/review.nvim/scripts/sync.lua request.json
local root = vim.fs.dirname(vim.fs.dirname(debug.getinfo(1, "S").source:sub(2)))
vim.opt.rtp:prepend(root)
local ok, result = pcall(function()
  assert(arg[1], "Supply a request JSON file")
  local request = vim.json.decode(table.concat(vim.fn.readfile(arg[1]), "\n"))
  return require("review.sync").apply(request)
end)
if not ok then
  io.stderr:write(tostring(result) .. "\n")
  vim.cmd("cquit 1")
else
  io.stdout:write(vim.json.encode(result) .. "\n")
  vim.cmd("qa!")
end
