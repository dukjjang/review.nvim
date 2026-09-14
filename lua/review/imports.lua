local M = {}

-- Recognize static imports in the module header. Stop at executable code so
-- text inside strings/functions is never mistaken for an import declaration.
function M.rows(lines)
  local rows, first, block_comment = {}, nil, false
  for row, line in ipairs(lines) do
    local text = vim.trim(line)
    if first then
      if text:match("^}%s*from%s*['\"].*['\"]%s*;?%s*$")
        or text:match("^from%s*['\"].*['\"]%s*;?%s*$") then
        for index = first, row do rows[index] = true end
        first = nil
      elseif not text:match("^[%w_%s{},*]+$") and text ~= "" then
        break -- Unrecognized syntax: retain it for review.
      end
    elseif block_comment then
      if text:find("*/", 1, true) then
        if not text:match("%*/%s*$") then break end
        block_comment = false
      end
    elseif text == "" or text:match("^//") then
      -- Header spacing/comments are not imports.
    elseif text:match("^/%*") then
      if not text:find("*/", 1, true) then block_comment = true
      elseif not text:match("%*/%s*$") then break end
    elseif text:match("^['\"]use [%w%s]+['\"];?$") then
      -- Module directives can precede imports.
    elseif text:match("^import%s+.*from%s*['\"].*['\"]%s*;?%s*$")
      or text:match("^import%s*['\"][^'\"]+['\"]%s*;?%s*$") then
      rows[row] = true
    elseif text:match("^import%s+[%w_%s{},*]+$") then
      first = row
    else
      break
    end
  end
  return rows
end

function M.only(hunk, before, after)
  if hunk.untracked then
    for row = hunk.first, hunk.first + hunk.length - 1 do
      if not after[row] then return false end
    end
    return true
  end
  local old, new, changed = hunk.old, hunk.first, false
  for line in (hunk.diff .. "\n"):gmatch("([^\n]*)\n") do
    local prefix = line:sub(1, 1)
    if prefix == "+" then
      if not after[new] then return false end
      changed, new = true, new + 1
    elseif prefix == "-" then
      if not before[old] then return false end
      changed, old = true, old + 1
    elseif prefix == " " then
      old, new = old + 1, new + 1
    end
  end
  return changed
end
return M
