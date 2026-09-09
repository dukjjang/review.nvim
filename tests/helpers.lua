local M = {}

function M.equal(actual, expected, message)
  assert(vim.deep_equal(actual, expected), message .. "\nexpected: " .. vim.inspect(expected) .. "\nactual: " .. vim.inspect(actual))
end

function M.editor_windows()
  local windows = {}
  for _, win in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_get_config(win).relative == "" then windows[#windows + 1] = win end
  end
  return windows
end

function M.press(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "xt", false)
end

function M.project()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  vim.fn.writefile({ "local function retry()", "  return false", "end", "", "local done = true" }, root .. "/a.lua")
  vim.fn.writefile({ "local result = false" }, root .. "/b with spaces.lua")
  local store = require("review.store")
  store.save(root, { version = 1, root = root, items = {
    { id = "retry", path = "a.lua", row = 1, anchor = { "local function retry()", "  return false", "end" }, title = "retry logic", status = "PENDING" },
    { id = "done", path = "a.lua", row = 5, anchor = { "local done = true" }, title = "already checked", status = "OK" },
    { id = "result", path = "b with spaces.lua", row = 1, anchor = { "local result = false" }, title = "result handling", status = "PENDING" },
  } }, nil)
  return root
end

function M.modeline_project()
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  vim.fn.writefile({
    "-- REVIEW: URL handling",
    "local url = 'https://example.test'",
    "-- REVIEW_END",
    "-- vim: 'https://example.test'",
  }, root .. "/url.lua")
  return root
end

function M.large_project(count)
  local root = vim.fn.tempname()
  vim.fn.mkdir(root, "p")
  root = vim.uv.fs_realpath(root)
  for index = 1, count do
    vim.fn.writefile({ "// REVIEW: item " .. index, "const value = 1;", "// REVIEW_END" },
      ("%s/%03d.ts"):format(root, index))
  end
  local entries = {}
  for index = 1, count do
    local path = ("%03d.ts"):format(index)
    vim.fn.writefile({ "const value = " .. index .. ";" }, root .. "/" .. path)
    entries[#entries + 1] = { id = tostring(index), path = path, row = 1,
      anchor = { "const value = " .. index .. ";" }, title = "item " .. index, status = "PENDING" }
  end
  require("review.store").save(root, { version = 1, root = root, items = entries }, nil)
  return root
end

return M
