local M = {}
local api = vim.api
local store = require("review.store")
local summary = require("review.summary")
local ns = api.nvim_create_namespace("review.nvim")
local config = { auto_advance = true, keymaps = true }
local watcher
local state = { items = {}, buffers = {}, active = false }
local groups = { PENDING = "ReviewPending", OK = "ReviewOK", REJECT = "ReviewReject" }

local function notify(message)
  vim.notify("review.nvim: " .. message, vim.log.levels.WARN)
end
local function guarded(fn)
  local ok, result = pcall(fn)
  if not ok then notify(tostring(result)); return end
  return result
end
local function root_for(buf)
  local path = api.nvim_buf_get_name(buf)
  local root = vim.fs.root(path ~= "" and path or vim.fn.getcwd(), ".git") or vim.fn.getcwd()
  return (vim.uv or vim.loop).fs_realpath(root) or root
end
local function colors()
  api.nvim_set_hl(0, "ReviewSummary", { link = "NormalFloat", default = true })
  api.nvim_set_hl(0, "ReviewCountOK", { fg = "#98c379", bold = true, default = true })
  api.nvim_set_hl(0, "ReviewCountPENDING", { fg = "#e5c07b", bold = true, default = true })
  api.nvim_set_hl(0, "ReviewCountREJECT", { fg = "#e06c75", bold = true, default = true })
  api.nvim_set_hl(0, "ReviewPending", { bg = "#583719", default = true })
  api.nvim_set_hl(0, "ReviewOK", { bg = "#203d2b", default = true })
  api.nvim_set_hl(0, "ReviewReject", { bg = "#54292e", default = true })
end
local function clear()
  for buf in pairs(state.buffers) do
    if api.nvim_buf_is_valid(buf) then api.nvim_buf_clear_namespace(buf, ns, 0, -1) end
  end
end

local function finder()
  return require("telescope.finders").new_table({
      results = vim.deepcopy(state.items),
      entry_maker = function(item)
        local label = ("[%s%s] %s:%d  %s"):format(item.status, item.stale and " · 위치 재확인" or "", item.path, item.row, item.title)
        return { value = item, display = label, ordinal = label, filename = state.root .. "/" .. item.path, lnum = item.row }
      end,
    })
end

function M.refresh()
  if not state.active then return end
  clear()
  state.items, state.buffers = {}, {}
  local contents = {}
  for _, saved in ipairs(state.data.items) do
    local path = state.root .. "/" .. saved.path
    if not saved.archived and (not state.scope or path == state.scope) then
      local buf = vim.fn.bufadd(path)
      state.buffers[buf] = true
      if contents[buf] == nil then
        if api.nvim_buf_is_loaded(buf) then
          contents[buf] = api.nvim_buf_get_lines(buf, 0, -1, false)
        else
          local ok, lines = pcall(vim.fn.readfile, path)
          contents[buf] = ok and lines or false
        end
      end
      local item = vim.deepcopy(saved)
      item.buf = buf
      local row = contents[buf] and store.locate(saved, contents[buf])
      item.stale = not row
      item.row = row or saved.row
      item.last = item.row + #item.anchor - 1
      state.items[#state.items + 1] = item
      if row and api.nvim_buf_is_loaded(buf) then
        api.nvim_buf_set_extmark(buf, ns, row - 1, 0, {
          end_row = item.last, hl_eol = true, hl_group = groups[item.status], priority = 110,
          virt_lines = { { { "REVIEW [" .. item.status .. "] " .. item.title, groups[item.status] } } },
          virt_lines_above = true,
        })
      end
    end
  end
  table.sort(state.items, function(a, b)
    if a.path == b.path then return a.row < b.row end
    return a.path < b.path
  end)
  summary.update(state.items)
  if state.picker and state.picker.prompt_bufnr and api.nvim_buf_is_valid(state.picker.prompt_bufnr) then
    state.picker:refresh(finder(), { reset_prompt = false })
  end
end

local function watch(root)
  if watcher then watcher:stop(); watcher:close(); watcher = nil end
  local directory = vim.fn.fnamemodify(store.path(root), ":h")
  vim.fn.mkdir(directory, "p")
  local handle = (vim.uv or vim.loop).new_fs_event()
  watcher = handle
  local filename = vim.fn.fnamemodify(store.path(root), ":t")
  local queued = false
  local ok, err = handle:start(directory, {}, function(failure, changed)
    if failure or (changed and changed ~= filename) or queued then return end
    queued = true
    vim.schedule(function()
      queued = false
      if watcher ~= handle or not state.active or state.root ~= root then return end
      guarded(function()
        local data, version = store.load(root)
        if version ~= state.version then
          state.data, state.version = data, version
          M.refresh()
        end
      end)
    end)
  end)
  if not ok then
    handle:close()
    watcher = nil
    notify("자동 갱신 감시를 시작하지 못했습니다. :Review로 다시 읽으세요: " .. tostring(err))
  end
end

local function selected()
  local buf, row = api.nvim_get_current_buf(), api.nvim_win_get_cursor(0)[1]
  for index, item in ipairs(state.items) do
    if not item.stale and item.buf == buf and row >= item.row and row <= item.last then return index, item end
  end
end
local function jump(id)
  M.refresh()
  for _, item in ipairs(state.items) do
    if item.id == id then
      if item.stale then
        state.relocate = item.id
        notify("위치 재확인: " .. item.title .. " · 해당 코드를 선택한 뒤 :ReviewRelocate")
        return
      end
      if not api.nvim_buf_is_loaded(item.buf) then
        local modelines = vim.o.modelines
        vim.o.modelines = 0
        local ok, err = pcall(vim.fn.bufload, item.buf)
        vim.o.modelines = modelines
        if not ok then notify(tostring(err)); return end
        -- Re-check the anchor after read hooks and external changes.
        return jump(id)
      end
      local win = state.source
      if not win or not api.nvim_win_is_valid(win) then win = api.nvim_get_current_win() end
      api.nvim_win_call(win, function()
        vim.cmd("hide buffer " .. item.buf)
        api.nvim_win_set_cursor(0, { item.row, 0 })
        vim.cmd("normal! zvzz")
      end)
      api.nvim_set_current_win(win)
      return
    end
  end
end

function M.close()
  if state.active then
    M.refresh()
    local _, item = selected()
    if item then
      local cursor = api.nvim_win_get_cursor(0)
      state.resume = { id = item.id, offset = cursor[1] - item.row, col = cursor[2] }
    end
  end
  state.active = false
  if watcher then watcher:stop(); watcher:close(); watcher = nil end
  clear()
  summary.close()
end
function M.stop()
  M.close()
  state = { items = {}, buffers = {}, active = false }
end
function M.open(opts)
  opts = opts or {}
  local root = opts.root and ((vim.uv or vim.loop).fs_realpath(opts.root) or vim.fs.normalize(opts.root))
    or (opts.reuse and state.root) or root_for(api.nvim_get_current_buf())
  return guarded(function()
    local data, version = store.load(root)
    clear()
    state.root, state.data, state.version = root, data, version
    state.source = api.nvim_get_current_win()
    if not opts.reuse then
      state.scope = opts.buffer and api.nvim_buf_get_name(0) or nil
      state.resume = nil
    end
    state.active = true
    watch(root)
    M.refresh()
    if not opts.no_jump then
      if opts.reuse and state.resume then
        jump(state.resume.id)
        local _, item = selected()
        if item and item.id == state.resume.id then
          local row = math.min(item.row + state.resume.offset, item.last)
          local line = api.nvim_buf_get_lines(item.buf, row - 1, row, false)[1]
          api.nvim_win_set_cursor(0, { row, math.min(state.resume.col, #line) })
        end
        return true
      end
      for _, item in ipairs(state.items) do
        if not item.stale and item.status == "PENDING" then jump(item.id); return true end
      end
      if state.items[1] then jump(state.items[1].id) end
    end
    return true
  end)
end
function M.toggle()
  if state.active then M.close() else M.open({ reuse = state.root ~= nil }) end
end
function M.next(direction)
  if not state.active then M.open({ reuse = state.root ~= nil }); return end
  M.refresh()
  local index = selected()
  for offset = 1, #state.items do
    local candidate = state.items[((index or (direction > 0 and 0 or 1)) - 1 + offset * direction) % #state.items + 1]
    if not candidate.stale then jump(candidate.id); return end
  end
  notify("이동할 리뷰가 없습니다. 위치 재확인 항목은 <leader>fr에서 확인하세요.")
end
function M.mark(status)
  assert(groups[status], "Invalid review status")
  if not state.active then notify("먼저 리뷰 모드에 진입하세요."); return end
  M.refresh()
  local index, item = selected()
  if not item then notify("리뷰 코드 범위 안에 커서를 두세요."); return end
  guarded(function()
    local updated = vim.deepcopy(state.data)
    for _, entry in ipairs(updated.items) do if entry.id == item.id then entry.status = status end end
    state.version = store.save(state.root, updated, state.version)
    state.data = updated
    M.refresh()
    if config.auto_advance and status ~= "PENDING" then
      for offset = 1, #state.items do
        local next_item = state.items[(index - 1 + offset) % #state.items + 1]
        if next_item.status == "PENDING" and not next_item.stale then jump(next_item.id); return end
      end
    end
  end)
end

-- Create/reattach reviews from selected code without inserting source markers.
function M.add(title, first, last, id)
  return guarded(function()
    local buf = api.nvim_get_current_buf()
    local path = api.nvim_buf_get_name(buf)
    assert(path ~= "" and vim.bo[buf].buftype == "", "A named source buffer is required")
    local root = root_for(buf)
    assert(path:sub(1, #root + 1) == root .. "/", "Source must be inside the project")
    first = first or api.nvim_win_get_cursor(0)[1]
    last = last or first
    local anchor = api.nvim_buf_get_lines(buf, first - 1, last, false)
    assert(#anchor > 0 and vim.trim(table.concat(anchor, "\n")) ~= "", "Select a nonempty code range")
    local data, version = store.load(root)
    local entry
    if id then
      for _, item in ipairs(data.items) do if item.id == id then entry = item end end
      assert(entry, "Review ID was not found in this project")
    else
      assert(title and vim.trim(title) ~= "", "A review description is required")
      entry = { id = vim.fn.sha256(path .. title .. tostring((vim.uv or vim.loop).hrtime())), title = title }
      data.items[#data.items + 1] = entry
    end
    entry.path, entry.row, entry.anchor, entry.status = path:sub(#root + 2), first, anchor, "PENDING"
    store.save(root, data, version)
    M.open({ root = root, no_jump = true })
    return entry.id
  end)
end

function M.import(opts)
  opts = opts or {}
  return guarded(function()
    local root = opts.root and ((vim.uv or vim.loop).fs_realpath(opts.root) or opts.root) or root_for(api.nvim_get_current_buf())
    local paths = {}
    if opts.buffer then
      paths = { api.nvim_buf_get_name(0) }
    else
      local result = vim.system({ "rg", "-l", "--null", "--glob", "!.git", [[^\s*(//|--|#|/\*|\*|<!--|;|%)\s*REVIEW(\[(OK|REJECT)\])?:]], root }):wait(10000)
      assert(result.code == 0 or result.code == 1, result.stderr)
      paths = vim.split(result.stdout or "", "\0", { trimempty = true })
    end
    local imported = 0
    for _, path in ipairs(paths) do
      local ok, err = pcall(function()
        local buf = vim.fn.bufadd(path)
        local modelines = vim.o.modelines
        vim.o.modelines = 0
        local loaded, failure = pcall(vim.fn.bufload, buf)
        vim.o.modelines = modelines
        assert(loaded, failure)
        local data, version = store.load(root)
        local remove = require("review.migrate").buffer(buf, root, data)
        if remove then
          store.save(root, data, version) -- Durable metadata before touching source.
          remove()
          imported = imported + 1
        end
      end)
      if not ok then notify(path .. ": " .. tostring(err)) end
    end
    M.open({ root = root, no_jump = true })
    vim.notify("review.nvim: " .. imported .. "개 파일의 리뷰를 로컬 데이터로 이전했습니다.")
    return imported
  end)
end

function M.pick(opts)
  local ok, pickers = pcall(require, "telescope.pickers")
  if not ok then notify("Install telescope.nvim to search review points"); return end
  if not M.open(vim.tbl_extend("force", opts or {}, { no_jump = true })) then return end
  if #state.items == 0 then notify("리뷰가 없습니다. :ReviewAdd 설명 또는 :ReviewImport로 등록하세요."); return end
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")
  state.picker = pickers.new({}, {
    prompt_title = "Reviews · PENDING / OK / REJECT / 위치 재확인",
    finder = finder(),
    sorter = require("telescope.config").values.generic_sorter({}),
    attach_mappings = function(prompt_buf)
      actions.select_default:replace(function()
        local entry = action_state.get_selected_entry()
        state.picker = nil
        actions.close(prompt_buf)
        if entry then jump(entry.value.id) end
      end)
      return true
    end,
  })
  state.picker:find()
end
function M.setup(opts)
  config = vim.tbl_extend("force", config, opts or {})
  colors()
  local group = api.nvim_create_augroup("ReviewNvim", { clear = true })
  api.nvim_create_autocmd("ColorScheme", { group = group, callback = colors })
  api.nvim_create_autocmd({ "VimResized", "TabEnter" }, {
    group = group, callback = function() if state.active then summary.update(state.items) end end,
  })
  api.nvim_create_autocmd({ "TextChanged", "TextChangedI", "BufWritePost", "BufEnter" }, {
    group = group, callback = function(event) if state.buffers[event.buf] then M.refresh() end end,
  })
  api.nvim_create_user_command("Review", function(args) M.open(args.args ~= "" and { root = args.args } or {}) end, { nargs = "?", complete = "dir" })
  api.nvim_create_user_command("ReviewBuffer", function() M.open({ buffer = true }) end, {})
  api.nvim_create_user_command("ReviewStop", M.stop, {})
  api.nvim_create_user_command("ReviewPick", function() M.pick() end, {})
  api.nvim_create_user_command("ReviewAdd", function(args) M.add(args.args, args.line1, args.line2) end, { nargs = "+", range = true })
  api.nvim_create_user_command("ReviewRelocate", function(args)
    local id = args.args ~= "" and args.args or state.relocate
    if not id then notify("먼저 검색창에서 위치 재확인 항목을 선택하세요."); return end
    M.add(nil, args.line1, args.line2, id)
  end, { nargs = "?", range = true })
  api.nvim_create_user_command("ReviewImport", function() M.import() end, {})
  api.nvim_create_user_command("ReviewImportBuffer", function() M.import({ buffer = true }) end, {})
  if config.keymaps then
    for _, mapping in ipairs({
      { "<leader>rv", M.toggle, "Toggle review mode" }, { "<leader>fr", M.pick, "Find review points" },
      { "]r", function() M.next(1) end, "Next review point" }, { "[r", function() M.next(-1) end, "Previous review point" },
      { "<leader>ro", function() M.mark("OK") end, "Review OK" }, { "<leader>rx", function() M.mark("REJECT") end, "Review reject" },
      { "<leader>ru", function() M.mark("PENDING") end, "Reset review decision" },
    }) do vim.keymap.set("n", mapping[1], mapping[2], { desc = mapping[3], silent = true }) end
  end
end
return M
