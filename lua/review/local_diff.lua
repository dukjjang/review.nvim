local M = {}
local api, uv = vim.api, vim.uv or vim.loop
local store = require("review.store")
local imports = require("review.imports")

local function git(root, args)
  local command = { "git", "--literal-pathspecs", "-C", root }
  vim.list_extend(command, args)
  local result = vim.system(command, { text = false }):wait(10000)
  assert(result.code == 0, result.stderr ~= "" and result.stderr or "Git diff failed")
  return result.stdout
end

local function excluded(path)
  for part in path:gmatch("[^/]+") do
    if part:sub(1, 1) == "." then return true end
  end
  local name = vim.fs.basename(path):lower()
  local lower = "/" .. path:lower() .. "/"
  for _, directory in ipairs({ "__tests__", "__mocks__", "__snapshots__", "test", "tests", "fixtures", "test-utils", "test_helpers" }) do
    if lower:find("/" .. directory .. "/", 1, true) then return true end
  end
  return name:match("%.test%.") or name:match("%.spec%.") or name:match("%.mocks?%.")
    or name:match("%.snap$") or name:match("^test_.*%.") or name:match("_test%.")
    or name:match("^jest%.") or name:match("^vitest%.") or name == "setuptests.ts"
    or name == "setuptests.js" or name == ".nvimlog" or name:match("%.log$")
end

local function read(path)
  local file = assert(io.open(path, "rb"), "Cannot read " .. path)
  local text = file:read("*a")
  file:close()
  return text
end

function M.apply(directory)
  local root = git(directory, { "rev-parse", "--show-toplevel" }):gsub("\n$", "")
  root = assert(uv.fs_realpath(root))
  local head = vim.system({ "git", "-C", root, "rev-parse", "--verify", "HEAD" }, { text = true }):wait()
  local base = head.code == 0 and vim.trim(head.stdout) or git(root, { "hash-object", "-t", "tree", "--stdin" }):gsub("\n$", "")
  local function inventory()
    local paths, seen = {}, {}
    for _, args in ipairs({
      { "diff", "--no-ext-diff", "--no-renames", "--name-only", "-z", base, "--" },
      { "ls-files", "--others", "--exclude-standard", "-z" },
    }) do
      for _, path in ipairs(vim.split(git(root, args), "\0", { plain = true, trimempty = true })) do
        if not seen[path] then paths[#paths + 1], seen[path] = path, true end
      end
    end
    table.sort(paths)
    return paths
  end
  local paths = inventory()
  local data, version = store.load(root)
  local used, snapshots, current = {}, {}, {}
  local counts = { created = 0, updated = 0, unchanged = 0, archived = 0, skipped = {}, root = root }
  for _, path in ipairs(paths) do
    local absolute = root .. "/" .. path
    local stat = uv.fs_lstat(absolute)
    if excluded(path) or not stat or stat.type ~= "file" or stat.size > 1024 * 1024 then
      counts.skipped[#counts.skipped + 1] = path .. " (테스트·로그, 삭제·비일반 파일 또는 1 MiB 초과)"
    else
      for _, buf in ipairs(api.nvim_list_bufs()) do
        assert(not (api.nvim_buf_get_name(buf) == absolute and vim.bo[buf].modified), "먼저 저장하세요: " .. path)
      end
      local text = read(absolute)
      snapshots[absolute] = text
      if text:find("\0", 1, true) then
        counts.skipped[#counts.skipped + 1] = path .. " (바이너리)"
      else
        local lines = vim.split(text, "\n", { plain = true })
        if lines[#lines] == "" then table.remove(lines) end
        local diff = git(root, { "diff", "--no-ext-diff", "--no-textconv", "--no-renames", "--unified=3", base, "--", path })
        local hunks = {}
        for line in (diff .. "\n"):gmatch("([^\n]*)\n") do
          local old, first, length = line:match("^@@ %-(%d+)[^ ]* %+(%d+),?(%d*) @@")
          if old then
            hunks[#hunks + 1] = { old = tonumber(old), first = tonumber(first), length = tonumber(length) or 1, diff = "" }
          elseif #hunks > 0 then
            hunks[#hunks].diff = hunks[#hunks].diff .. line .. "\n"
          end
        end
        if diff == "" and #lines > 0 then hunks = { { old = 0, first = 1, length = #lines, diff = text, untracked = true } } end
        if #hunks == 0 then counts.skipped[#counts.skipped + 1] = path .. " (텍스트 변경 구간 없음)" end
        local before, after = {}, {}
        if path:match("%.[cm]?[jt]sx?$") then
          local result = vim.system({ "git", "-C", root, "show", base .. ":" .. path }, { text = false }):wait(10000)
          if result.code == 0 then before = imports.rows(vim.split(result.stdout, "\n", { plain = true })) end
          after = imports.rows(lines)
        end
        for _, hunk in ipairs(hunks) do
          local import_only = imports.only(hunk, before, after)
          local first, last
          if hunk.untracked then
            first, last = hunk.first, hunk.first + hunk.length - 1
          else
            local row = hunk.first
            for line in (hunk.diff .. "\n"):gmatch("([^\n]*)\n") do
              local prefix = line:sub(1, 1)
              if prefix == "+" then
                first, last = first or row, row
                row = row + 1
              elseif prefix == " " then
                row = row + 1
              end
            end
          end
          local anchor = first and vim.list_slice(lines, first, last) or {}
          if import_only then
            counts.skipped[#counts.skipped + 1] = path .. ":" .. hunk.first .. " (import 변경만 있는 구간)"
          elseif not first then
            counts.skipped[#counts.skipped + 1] = path .. ":" .. hunk.first .. " (삭제만 있는 구간 — 주변 코드는 변경되지 않음)"
          elseif #anchor > 0 and vim.trim(table.concat(anchor, "\n")) ~= "" and store.locate({ anchor = anchor }, lines) == first then
            local item
            -- Preserve decisions only for the same HEAD and unchanged code.
            for _, old in ipairs(data.items) do
              if old.source == "local-diff" and old.base == base and old.path == path and not used[old.id]
                and not old.archived and old.diff == hunk.diff and vim.deep_equal(old.anchor, anchor) then item = old; break end
            end
            local key = vim.fn.sha256("local-diff\n" .. base .. "\n" .. path .. "\n" .. hunk.old)
            if not item then
              for _, old in ipairs(data.items) do if old.id == key and not used[old.id] then item = old; break end end
            end
            if not item then
              item = { id = key, source = "local-diff", base = base, path = path }
              data.items[#data.items + 1] = item
              counts.created = counts.created + 1
            elseif not item.archived and item.diff == hunk.diff and vim.deep_equal(item.anchor, anchor) then
              counts.unchanged = counts.unchanged + 1
            else
              counts.updated = counts.updated + 1
              item.previous_status = item.status
              item.status = "PENDING"
            end
            item.status = item.status or "PENDING"
            item.anchor, item.row, item.diff = anchor, first, hunk.diff
            item.title = "로컬 변경 · " .. vim.fs.basename(path) .. " · 추가·수정된 코드 확인"
            item.archived, item.archive_reason = nil, nil
            used[item.id], current[item.id] = true, true
          else
            counts.skipped[#counts.skipped + 1] = path .. ":" .. hunk.first .. " (빈 범위 또는 중복 코드로 위치 불명확)"
          end
        end
      end
    end
  end
  for _, item in ipairs(data.items) do
    if item.source == "local-diff" and not item.archived and not current[item.id] then
      item.archived, item.archive_reason = true, "현재 로컬 diff에서 사라진 항목"
      counts.archived = counts.archived + 1
    end
  end
  assert(vim.deep_equal(paths, inventory()), "로컬 변경 파일 목록이 바뀌었습니다. 다시 실행하세요.")
  for path, text in pairs(snapshots) do assert(read(path) == text, "파일이 바뀌었습니다. 다시 실행하세요: " .. path) end
  local final = vim.system({ "git", "-C", root, "rev-parse", "--verify", "HEAD" }, { text = true }):wait()
  assert(final.code == head.code and final.stdout == head.stdout, "HEAD가 바뀌었습니다. 다시 실행하세요.")
  store.save(root, data, version)
  return counts
end
return M
