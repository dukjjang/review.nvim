local M = {}
local api = vim.api
local ns = api.nvim_create_namespace("review.summary")
local buf, win

function M.close()
  if win and api.nvim_win_is_valid(win) then api.nvim_win_close(win, true) end
  win = nil
end

function M.update(items)
  if win and api.nvim_win_is_valid(win) and api.nvim_win_get_tabpage(win) ~= api.nvim_get_current_tabpage() then
    M.close()
  end
  local counts = { OK = 0, PENDING = 0, REJECT = 0 }
  for _, item in ipairs(items) do counts[item.status] = counts[item.status] + 1 end
  local text = (" REVIEW  OK %d | PENDING %d | REJECT %d "):format(counts.OK, counts.PENDING, counts.REJECT)
  local stale = 0
  for _, item in ipairs(items) do if item.stale then stale = stale + 1 end end
  if stale > 0 then text = text .. " | 위치 재확인 " .. stale end
  if not buf or not api.nvim_buf_is_valid(buf) then
    buf = api.nvim_create_buf(false, true)
    vim.bo[buf].filetype = "review_summary"
    vim.bo[buf].bufhidden = "hide"
  end
  vim.bo[buf].modifiable = true
  api.nvim_buf_set_lines(buf, 0, -1, false, { text })
  vim.bo[buf].modifiable = false
  api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, status in ipairs({ "OK", "PENDING", "REJECT" }) do
    local first, last = text:find(status .. " " .. counts[status], 1, true)
    api.nvim_buf_set_extmark(buf, ns, 0, first - 1, {
      end_col = last, hl_group = "ReviewCount" .. status,
    })
  end
  local width = math.min(vim.fn.strdisplaywidth(text), vim.o.columns)
  local opts = {
    relative = "editor", row = 0, col = vim.o.columns - width,
    width = width, height = 1, focusable = false, style = "minimal", zindex = 40,
  }
  if win and api.nvim_win_is_valid(win) then
    api.nvim_win_set_config(win, opts)
  else
    win = api.nvim_open_win(buf, false, opts)
    vim.wo[win].wrap = false
    vim.wo[win].winhighlight = "Normal:ReviewSummary"
  end
end

return M
