local plugin = vim.fn.getcwd()
vim.opt.rtp:prepend(plugin)
package.path = plugin .. "/tests/?.lua;" .. package.path
vim.env.XDG_DATA_HOME = vim.fn.tempname()
local h, api = require("helpers"), vim.api
local root = h.project()
local store, sync, review = require("review.store"), require("review.sync"), require("review")
review.setup({ auto_advance = false })
local function entry(id)
  for _, item in ipairs(store.load(root).items) do if item.id == id then return item end end
end
local request = { root = root, task = "test-feature", items = {
  { key = "retry", path = "a.lua", first = 1, last = 3, title = "재시도 실패 동작 확인" },
} }
local ok, err = xpcall(function()
  local original = vim.fn.readfile(root .. "/a.lua")
  h.equal(sync.apply(request).created, 1, "New AI review must be added")
  local id = vim.fn.sha256("ai\ntest-feature\nretry")
  h.equal(entry(id).status, "PENDING", "AI review starts pending")
  local data, version = store.load(root)
  for _, item in ipairs(data.items) do if item.id == id then item.status = "OK" end end
  store.save(root, data, version)
  h.equal(sync.apply(request).unchanged, 1, "Same request should not duplicate or reset")
  h.equal(entry(id).status, "OK", "User approval must survive unchanged sync")
  vim.fn.writefile({ "-- inserted above", unpack(original) }, root .. "/a.lua")
  request.items[1].first, request.items[1].last = 2, 4
  sync.apply(request)
  h.equal(entry(id).status, "OK", "Moving unchanged code must preserve approval")
  vim.fn.writefile({ "-- inserted above", "local function retry()", "  return true", "end", "", "local done = true" }, root .. "/a.lua")
  h.equal(sync.apply(request).updated, 1, "Changed code must update the existing review")
  h.equal(entry(id).status, "PENDING", "Changed code must request human review again")
  h.equal(entry("done").status, "OK", "Unrelated manual reviews must be preserved")
  h.equal(#store.load(root).items, 4, "Partial upsert must preserve omitted entries")
  local before = vim.fn.readfile(store.path(root))
  local invalid = vim.deepcopy(request)
  invalid.items[2] = { key = "invalid", path = "../outside", first = 1, last = 1, title = "Invalid" }
  assert(not pcall(sync.apply, invalid))
  h.equal(vim.fn.readfile(store.path(root)), before, "Invalid batch must write nothing")
  sync.apply({ root = root, task = request.task, items = {}, archive = { { id = id, reason = "기능 삭제" } } })
  assert(entry(id).archived, "Removed feature must be archived, not lost")
  sync.apply(request)
  assert(not entry(id).archived and entry(id).status == "PENDING", "Reintroduced feature must need review")

  vim.cmd("cd " .. vim.fn.fnameescape(root))
  vim.cmd.edit(root .. "/a.lua")
  review.open({ root = root })
  local focused = api.nvim_get_current_win()
  local manifest = vim.fn.tempname() .. ".json"
  local update = { root = root, task = request.task, items = {
    { id = id, path = "a.lua", first = 2, last = 4, title = "외부 AI가 설명을 갱신함" },
  } }
  vim.fn.writefile({ vim.json.encode(update) }, manifest)
  local result = vim.system({ vim.v.progpath, "--headless", "-u", "NONE", "-i", "NONE", "-l", plugin .. "/scripts/sync.lua", manifest }):wait()
  assert(result.code == 0, result.stderr)
  assert(vim.wait(3000, function()
    for _, mark in ipairs(api.nvim_buf_get_extmarks(0, api.nvim_get_namespaces()["review.nvim"], 0, -1, { details = true })) do
      if mark[4].virt_lines and mark[4].virt_lines[1][1][1]:find("외부 AI가 설명을 갱신함", 1, true) then return true end
    end
  end, 10), "External CLI sync must refresh the live review without reopening")
  h.equal(api.nvim_get_current_win(), focused, "Background refresh must preserve focus")
  assert(not vim.bo.modified, "Sync must not dirty source buffers")
  vim.fn.delete(manifest)
  review.stop()
end, debug.traceback)
vim.fn.delete(root, "rf")
vim.fn.delete(vim.env.XDG_DATA_HOME, "rf")
if not ok then io.stderr:write(err .. "\n"); vim.cmd("cquit 1") end
print("PASS: idempotent AI upsert, re-review changed code, preserve decisions, archive, atomic validation and live CLI refresh")
vim.cmd("qa!")
