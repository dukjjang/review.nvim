local M = {}
local api = vim.api

function M.buffer(buf, root, data)
  local was_modified = vim.bo[buf].modified
  local tick = api.nvim_buf_get_changedtick(buf)
  local buffer_lines = api.nvim_buf_get_lines(buf, 0, -1, false)
  assert(not vim.bo[buf].readonly and vim.bo[buf].modifiable and vim.bo[buf].buftype == "", "Source is not writable")
  local path = api.nvim_buf_get_name(buf)
  assert(path:sub(1, #root + 1) == root .. "/", "Source is outside this project")
  local file = assert(io.open(path, "rb"))
  local original = file:read("*a")
  file:close()
  if not was_modified then
    assert(vim.deep_equal(vim.fn.readfile(path), buffer_lines), "Source changed on disk; reload it before importing")
  end
  local entries, clean = require("review.parser").extract(buf)
  if #entries == 0 then return nil end
  local relative = path:sub(#root + 2)
  for _, item in ipairs(entries) do
    item.path = relative
    item.id = vim.fn.sha256(relative .. "\n" .. item.title .. "\n" .. table.concat(item.anchor, "\n"))
    local exists = false
    for _, existing in ipairs(data.items) do if existing.id == item.id then exists = true; break end end
    if not exists then data.items[#data.items + 1] = item end
  end
  local directory = vim.fn.stdpath("data") .. "/review/backups/" .. vim.fn.sha256(root)
  vim.fn.mkdir(directory, "p")
  local backup = directory .. "/" .. vim.fn.sha256(path .. "\n" .. original) .. ".source"
  local output = assert(io.open(backup, "wb"))
  local written, err = output:write(original)
  local closed, close_err = output:close()
  assert(written and closed, err or close_err)
  local verify = assert(io.open(backup, "rb"))
  local saved = verify:read("*a")
  verify:close()
  assert(saved == original, "Review backup verification failed")
  -- Preserve unsaved work separately, before removing only marker lines in memory.
  local buffer_backup = directory .. "/" .. vim.fn.sha256(path .. vim.json.encode(buffer_lines)) .. ".buffer.json"
  assert(vim.fn.writefile({ vim.json.encode({ path = path, lines = buffer_lines }) }, buffer_backup) == 0)
  assert(vim.deep_equal(vim.json.decode(table.concat(vim.fn.readfile(buffer_backup), "\n")).lines, buffer_lines))
  return function()
    local latest = assert(io.open(path, "rb"))
    local unchanged = latest:read("*a") == original
    latest:close()
    assert(unchanged and api.nvim_buf_get_changedtick(buf) == tick, "Source changed during import; comments were preserved")
    api.nvim_buf_set_lines(buf, 0, -1, false, clean)
    -- This explicit migration writes only removed markers, not formatting hooks.
    if not was_modified then
      api.nvim_buf_call(buf, function() vim.cmd("silent noautocmd keepalt keepjumps write") end)
    else
      vim.notify("review.nvim: 주석을 버퍼에서 이전했습니다. 기존 코드 수정은 저장하지 않았습니다: " .. path)
    end
  end
end

return M
