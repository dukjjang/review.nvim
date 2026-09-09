local M = {}

local prefixes = { "//", "--", "#", "/*", "*", "<!--", ";", "%" }

local function comment(line)
  local trimmed = line:match("^%s*(.*)")
  for _, prefix in ipairs(prefixes) do
    if trimmed:sub(1, #prefix) == prefix then
      return vim.trim(trimmed:sub(#prefix + 1):gsub("%*/%s*$", ""):gsub("%-%->%s*$", ""))
    end
  end
end

local function marker(line)
  local body = comment(line)
  if not body then return end
  if body == "REVIEW_END" then return { ending = true } end
  local status, title = body:match("^REVIEW%[([A-Z]+)%]:%s*(.*)$")
  if status == "OK" or status == "REJECT" then
    return { status = status, title = title }
  end
  title = body:match("^REVIEW:%s*(.*)$")
  if title then return { status = "PENDING", title = title } end
end

local function inferred_end(buf, lines, first, limit)
  local start = first + 1
  while start <= limit and (lines[start]:match("^%s*$") or comment(lines[start])) do
    start = start + 1
  end
  if start > limit then return first end
  local ok, parser
  if vim.api.nvim_buf_is_loaded(buf) then ok, parser = pcall(vim.treesitter.get_parser, buf) end
  if ok and parser then
    local parsed, trees = pcall(parser.parse, parser)
    if parsed and trees[1] then
      local col = #(lines[start]:match("^%s*"))
      local node = trees[1]:root():named_descendant_for_range(start - 1, col, start - 1, col)
      local last
      while node and node:parent() do
        local sr, _, er, ec = node:range()
        if sr ~= start - 1 then break end
        local finish = er + (ec > 0 and 1 or 0)
        if finish <= limit then last = finish end
        node = node:parent()
      end
      if last then return last end
    end
  end
  local last = start
  while last < limit and not lines[last + 1]:match("^%s*$") do last = last + 1 end
  return last
end

function M.parse(buf)
  local lines
  if vim.api.nvim_buf_is_loaded(buf) then
    lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  else
    local ok, result = pcall(vim.fn.readfile, vim.api.nvim_buf_get_name(buf))
    if not ok then
      vim.notify("review.nvim: could not read " .. vim.api.nvim_buf_get_name(buf) .. ": " .. tostring(result), vim.log.levels.WARN)
      return {}
    end
    lines = result
  end
  local markers, items = {}, {}
  for row, line in ipairs(lines) do
    local point = marker(line)
    if point then
      point.row = row
      markers[#markers + 1] = point
    end
  end
  for index, point in ipairs(markers) do
    if not point.ending then
      local following = markers[index + 1]
      local limit = following and following.row - 1 or #lines
      items[#items + 1] = {
        buf = buf, row = point.row,
        last = following and following.ending and following.row or inferred_end(buf, lines, point.row, limit),
        status = point.status, title = point.title,
      }
    end
  end
  return items
end

function M.extract(buf)
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  local items = M.parse(buf)
  local clean, positions = {}, {}
  for row, line in ipairs(lines) do
    if not marker(line) then
      clean[#clean + 1] = line
      positions[row] = #clean
    end
  end
  local result = {}
  for _, item in ipairs(items) do
    local anchor, row = {}, nil
    for original = item.row + 1, item.last do
      if positions[original] then
        row = row or positions[original]
        anchor[#anchor + 1] = lines[original]
      end
    end
    assert(row and #anchor > 0, "Review marker has no code to attach to: " .. item.title)
    result[#result + 1] = { row = row, anchor = anchor, title = item.title, status = item.status }
  end
  return result, clean
end

return M
