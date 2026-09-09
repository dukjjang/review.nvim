local M = {}
local uv = vim.uv or vim.loop
local statuses = { PENDING = true, OK = true, REJECT = true }

function M.path(root)
  return vim.fn.stdpath("data") .. "/review/" .. vim.fn.sha256(root) .. ".json"
end

local function read(path)
  local file = io.open(path, "rb")
  if not file then
    if uv.fs_stat(path) then error("Cannot read review data: " .. path) end
    return nil
  end
  local text = file:read("*a")
  file:close()
  return text
end

function M.load(root)
  local text = read(M.path(root))
  if not text then return { version = 1, root = root, items = {} }, nil end
  local data = vim.json.decode(text)
  assert(type(data) == "table" and data.version == 1 and data.root == root and type(data.items) == "table", "Invalid review data")
  local ids = {}
  for _, item in ipairs(data.items) do
    assert(type(item.id) == "string" and not ids[item.id] and type(item.path) == "string"
      and item.path ~= "" and item.path:sub(1, 1) ~= "/" and not ("/" .. item.path .. "/"):find("/../", 1, true)
      and type(item.title) == "string" and statuses[item.status]
      and type(item.row) == "number" and item.row >= 1 and item.row % 1 == 0
      and type(item.anchor) == "table" and #item.anchor > 0, "Invalid review entry")
    for _, line in ipairs(item.anchor) do assert(type(line) == "string", "Invalid review anchor") end
    ids[item.id] = true
  end
  return data, text
end

function M.save(root, data, previous)
  local path = M.path(root)
  vim.fn.mkdir(vim.fn.fnamemodify(path, ":h"), "p")
  local lock = path .. ".lock"
  assert(uv.fs_mkdir(lock, 448), "Review data is being written by another editor: " .. lock)
  local temporary = path .. "." .. vim.fn.getpid() .. ".tmp"
  local ok, result = xpcall(function()
    assert(read(path) == previous, "Review data changed in another editor; reopen the review before retrying")
    local text = vim.json.encode(data)
    local file = assert(io.open(temporary, "wb"))
    local written, err = file:write(text)
    local closed, close_err = file:close()
    assert(written and closed, err or close_err)
    assert(uv.fs_rename(temporary, path))
    return text
  end, debug.traceback)
  uv.fs_unlink(temporary)
  uv.fs_rmdir(lock)
  if not ok then error(result) end
  return result
end

-- Exact, unique code anchors survive inserted lines and editor restarts.
-- Changed or duplicated blocks require explicit reattachment.
function M.locate(item, lines)
  local found
  for row = 1, #lines - #item.anchor + 1 do
    local matches = true
    for offset, line in ipairs(item.anchor) do
      if lines[row + offset - 1] ~= line then matches = false; break end
    end
    if matches then
      if found then return nil end
      found = row
    end
  end
  return found
end

return M
