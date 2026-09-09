local M = {}
local store = require("review.store")
local uv = vim.uv or vim.loop

local function read(path)
  local ok, lines = pcall(vim.fn.readfile, path)
  assert(ok, "Cannot read source: " .. path)
  return lines
end

-- Partial upsert: omitted entries are preserved, never implicitly removed.
function M.apply(request)
  assert(type(request) == "table" and type(request.root) == "string", "root is required")
  local root = assert(uv.fs_realpath(request.root), "Project root does not exist")
  assert(type(request.task) == "string" and vim.trim(request.task) ~= "", "A stable task key is required")
  assert(type(request.items) == "table", "items must be an array")
  local data, version = store.load(root)
  local existing, used, snapshots = {}, {}, {}
  for _, item in ipairs(data.items) do existing[item.id] = item end
  local counts = { created = 0, updated = 0, unchanged = 0, archived = 0 }
  local function unique(id)
    assert(not used[id], "Duplicate review ID in request: " .. id)
    used[id] = true
  end
  for _, input in ipairs(request.items) do
    assert(type(input) == "table" and type(input.title) == "string" and vim.trim(input.title) ~= "", "Each item needs a description")
    assert(type(input.path) == "string" and input.path ~= "" and input.path:sub(1, 1) ~= "/"
      and not ("/" .. input.path .. "/"):find("/../", 1, true), "Source path must be project-relative")
    local path = assert(uv.fs_realpath(root .. "/" .. input.path), "Source does not exist: " .. input.path)
    assert(path:sub(1, #root + 1) == root .. "/", "Source resolves outside the project")
    local id = input.id
    if id then
      assert(type(id) == "string" and existing[id], "Existing review ID was not found")
    else
      assert(type(input.key) == "string" and vim.trim(input.key) ~= "", "New reviews need a stable key")
      id = vim.fn.sha256("ai\n" .. request.task .. "\n" .. input.key)
    end
    unique(id)
    local lines = snapshots[path] or read(path)
    snapshots[path] = lines
    local first, last = input.first, input.last
    assert(type(first) == "number" and type(last) == "number" and first % 1 == 0 and last % 1 == 0
      and first >= 1 and last >= first and last <= #lines, "Invalid source range for " .. input.path)
    local anchor = {}
    for row = first, last do anchor[#anchor + 1] = lines[row] end
    assert(vim.trim(table.concat(anchor, "\n")) ~= "", "Select meaningful code, not an empty range")
    assert(store.locate({ anchor = anchor }, lines) == first, "Ambiguous code range; include more surrounding code")
    local item = existing[id]
    local changed = not item or item.archived or item.path ~= input.path or item.title ~= input.title
      or not vim.deep_equal(item.anchor, anchor)
    if not item then
      item = { id = id, source = "ai", task = request.task, key = input.key }
      data.items[#data.items + 1] = item
      counts.created = counts.created + 1
    elseif changed then
      counts.updated = counts.updated + 1
      item.previous_status = item.status
    else
      counts.unchanged = counts.unchanged + 1
    end
    item.path, item.row, item.anchor, item.title = input.path, first, anchor, input.title
    item.archived, item.archive_reason = nil, nil
    if changed then item.status = "PENDING"; item.updated_at = os.date("!%Y-%m-%dT%H:%M:%SZ") end
  end
  for _, input in ipairs(request.archive or {}) do
    assert(type(input) == "table" and type(input.id) == "string" and existing[input.id], "Archive requires an existing review ID")
    assert(type(input.reason) == "string" and vim.trim(input.reason) ~= "", "Archive requires a reason")
    unique(input.id)
    existing[input.id].archived = true
    existing[input.id].archive_reason = input.reason
    counts.archived = counts.archived + 1
  end
  for path, lines in pairs(snapshots) do
    assert(vim.deep_equal(read(path), lines), "Source changed during review synchronization; retry from the final diff")
  end
  store.save(root, data, version)
  counts.path = store.path(root)
  return counts
end

return M
