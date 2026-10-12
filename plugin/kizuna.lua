-- kizuna: kizuna's directory of running AI agents, inside ranma.
--
-- Reads `kizuna peers --json` every few seconds (every agent kizuna launched:
-- its profile, repo, branch, busy or idle, who launched it, its ranma pane),
-- and:
--   - badges each agent's pane with its profile: ● busy, ○ idle, ? waiting
--     on you (a permission prompt), ◇ no state;
--     "pro2 +2" for a lead of two workers, "pro⤷max" for a worker that
--     a max agent launched;
--   - the `kizuna` bar module counts the agents, the idle ones and the ones
--     waiting on you, and a click opens the picker (put it on the bar with
--     ranma.bar { right = { "kizuna", ... } });
--   - the picker (`:kizuna` in the palette, or a click on the module) lists
--     every agent; pick one to focus its pane, message it (kizuna send, the
--     text typed in a prompt), message its lead instead when it is a worker,
--     or copy its id. `:kizuna-send <id>` messages one directly.
-- To bind a key: ranma.bind("u", function() ranma.emit("kizuna_open") end,
-- { desc = "kizuna", exit = true }).
--
-- With agents.ranma's badges on, busy and idle are left to it (its ● and ?)
-- and this badge keeps to who the agent is, plus ? for waiting, a state
-- agents.ranma does not know (kizuna.badge_state). The two badges sit side by
-- side, one per plugin. A pane number kizuna reports from another ranma
-- server is not badged here. Without a `kizuna` binary the plugin says so
-- once and stays quiet.
--
-- ranma's plugin API: https://github.com/masshirodev/ranma/blob/main/doc/CONFIG.md ("Pane
-- handles", "Pickers and prompts", "Timers and processes", "The bar").

ranma.option("kizuna.poll", {
  type = "int", min = 2, max = 60, default = 5, slider = false,
  name = "Look every", desc = "Seconds between two looks at the agents (kizuna peers takes a second or two).",
})
ranma.option("kizuna.badges", {
  type = "bool", default = true,
  name = "Badges", desc = "Mark each agent's pane with its profile, its state and who launched it.",
})
ranma.option("kizuna.badge_state", {
  type = "enum", choices = { "auto", "always", "never" }, default = "auto",
  name = "State in the badge",
  desc = "Busy, idle or waiting in the badge's glyph: auto leaves busy and idle to agents.ranma when its badges are on.",
})
ranma.option("kizuna.command", {
  type = "string", default = "kizuna",
  name = "Command", desc = "The kizuna binary (ai is the same program under its older name).",
})

local OWNER = "kizuna"
-- What a picker row holds for label and detail together: ranma's picker is
-- 72 cells wide, less its border, padding and the gap between the two.
local PICKER = 64

local state = {
  peers = {},      -- the last `kizuna peers --json`, in its order
  by_id = {},      -- id -> peer
  loaded = false,  -- one answer has come back
  missing = false, -- no kizuna binary: stop looking
  running = false, -- a look is under way; never two at once
  error = nil,     -- the last error said, so it is said once
}
local badged = {}  -- pane id -> true, what this plugin has marked
local verdicts = {} -- "id:pid" -> whether the agent's pane is in this server
local timer = nil

-- The first line of a tool's complaint.
local function first_line(s)
  return (tostring(s or ""):match("[^\n]+") or ""):gsub("^%s+", "")
end

local function complain(msg)
  if msg == state.error then return end
  state.error = msg
  ranma.notify("kizuna peers: " .. msg)
end

local function cut(s, n)
  local len = utf8.len(s)
  if not len or len <= n then return s end
  return s:sub(1, utf8.offset(s, n + 1) - 1)
end

-- Terminal cells, near enough: East Asian wide and emoji code points take two.
local WIDE = {
  { 0x1100, 0x115F }, { 0x2E80, 0xA4CF }, { 0xAC00, 0xD7A3 }, { 0xF900, 0xFAFF },
  { 0xFE30, 0xFE4F }, { 0xFF00, 0xFF60 }, { 0xFFE0, 0xFFE6 }, { 0x1F300, 0x1FAFF },
  { 0x20000, 0x3FFFD },
}
local function cells(cp)
  for _, r in ipairs(WIDE) do
    if cp >= r[1] and cp <= r[2] then return 2 end
  end
  return 1
end

local function width(s)
  local ok, w = pcall(function()
    local n = 0
    for _, cp in utf8.codes(s) do n = n + cells(cp) end
    return n
  end)
  return ok and w or #s
end

-- The longest start of s that fits in n cells, with "…" when it is cut.
local function fit(s, n)
  if width(s) <= n then return s end
  local out, used = {}, 0
  for _, cp in utf8.codes(s) do
    local c = cells(cp)
    if used + c > n - 1 then break end
    out[#out + 1] = utf8.char(cp)
    used = used + c
  end
  return table.concat(out) .. "…"
end

local function read(path)
  local f = io.open(path, "rb")
  if not f then return nil end
  local s = f:read("a")
  f:close()
  return s
end

local own_pid = nil
local function me()
  if own_pid == nil then
    own_pid = tonumber((read("/proc/self/stat") or ""):match("^(%d+)")) or false
  end
  return own_pid or nil
end

-- kizuna reports a pane number, not which ranma server it is in, and pane
-- numbers repeat between servers. A pane's processes carry RANMA, the pid of
-- the server that started it: when that is another ranma server still
-- running, the number is not one of ours. After an upgrade the old pid is
-- gone, and the pane is ours.
local function ours(peer)
  local pid = tonumber(peer.pid)
  if not pid or not me() then return true end
  local key = peer.id .. ":" .. pid
  if verdicts[key] == nil then
    local env = read("/proc/" .. pid .. "/environ") or ""
    local server = tonumber(("\0" .. env):match("\0RANMA=(%d+)") or "")
    local other = server and server ~= me()
      and (read("/proc/" .. server .. "/cmdline") or ""):find("ranma\0server", 1, true) ~= nil
    verdicts[key] = not other
  end
  return verdicts[key]
end

local function pane_of(peer)
  local id = tonumber(peer.pane)
  if not id or not ours(peer) then return nil end
  return ranma.pane(id)
end

local function profile_of(id)
  return (id or ""):match("^([^/]+)") or id or "?"
end

-- Who it is, in a badge's 12 characters: its profile, then the profile that
-- launched it or how many it launched. A launcher's name that does not fit
-- goes whole, never cut to a misleading part ("opencode3⤷"; the picker names
-- it).
local function word(peer)
  local w = peer.profile or peer.provider or "?"
  if peer.lead then
    local full = w .. "⤷" .. profile_of(peer.lead)
    w = utf8.len(full) <= 12 and full or (cut(w, 11) .. "⤷")
  elseif peer.workers and #peer.workers > 0 then
    w = w .. " +" .. #peer.workers
  end
  return cut(w, 12)
end

local function shows_state()
  local mode = ranma.get("kizuna.badge_state")
  if mode == "always" then return "all" end
  if mode == "never" then return "none" end
  local ok, on = pcall(ranma.get, "agents.badges")
  return (ok and on == true) and "waiting" or "all"
end

-- with_state: "all", "waiting" (agents.ranma shows busy and idle but knows
-- nothing of waiting), or "none".
local function glyph(peer, with_state)
  if peer.state == "waiting" and with_state ~= "none" then return "?", "urgent" end
  if with_state == "all" then
    if peer.state == "busy" then return "●", "accent" end
    if peer.state == "idle" then return "○", "dim" end
  end
  return "◇", "normal"
end

local function unbadge(id)
  local p = ranma.pane(id)
  if p then pcall(p.badge, p, OWNER) end
end

local function badge_all()
  local now = {}
  if ranma.get("kizuna.badges") then
    local with_state = shows_state()
    for _, peer in ipairs(state.peers) do
      local p = pane_of(peer)
      if p then
        local g, role = glyph(peer, with_state)
        if pcall(p.badge, p, OWNER, g, word(peer), role) then now[p.id] = true end
      end
    end
  end
  for id in pairs(badged) do
    if not now[id] then unbadge(id) end
  end
  badged = now
end

local function update(peers)
  state.peers, state.by_id, state.loaded = {}, {}, true
  for _, peer in ipairs(peers) do
    if type(peer) == "table" and type(peer.id) == "string" then
      state.peers[#state.peers + 1] = peer
      state.by_id[peer.id] = peer
    end
  end
  badge_all()
end

local function stop()
  if timer then ranma.cancel(timer) end
  timer = nil
  state.peers, state.by_id = {}, {}
  badge_all()
end

local function poll()
  if state.missing or state.running then return end
  local cmd = ranma.get("kizuna.command")
  state.running = true
  ranma.spawn({ cmd, "peers", "--json" }, { timeout = 15, on_exit = function(r)
    state.running = false
    if r.error and r.error:match("could not run") then
      state.missing = true
      stop()
      ranma.toast("kizuna.ranma: no `" .. cmd .. "` here, so no agents to show (reload once it is installed)")
      return
    end
    if r.code ~= 0 then
      return complain(first_line(r.error or (r.stderr ~= "" and r.stderr) or ("exit " .. tostring(r.code))))
    end
    local ok, peers = pcall(ranma.json.decode, r.stdout or "")
    if not ok or type(peers) ~= "table" then return complain("not the JSON it should print") end
    state.error = nil
    update(peers)
  end })
end

local function counts()
  local idle, busy, waiting = 0, 0, 0
  for _, peer in ipairs(state.peers) do
    if peer.state == "idle" then idle = idle + 1
    elseif peer.state == "busy" then busy = busy + 1
    elseif peer.state == "waiting" then waiting = waiting + 1 end
  end
  return #state.peers, idle, busy, waiting
end

local function role_of(peer)
  if peer.lead then
    return "worker of " .. peer.lead .. (state.by_id[peer.lead] and "" or " (ended)")
  end
  if peer.workers and #peer.workers > 0 then return "lead of " .. #peer.workers end
  return nil
end

-- The message goes in on stdin, so no text of it is ever read as a flag.
local function send(id, worker)
  ranma.input {
    title = "message " .. id,
    on_submit = function(text)
      if not text:match("%S") then return end
      local script = [[printf '%s' "$1" | exec "$2" send ]] .. (worker and "--worker " or "") .. [["$3"]]
      ranma.spawn({ "sh", "-c", script, "sh", text, ranma.get("kizuna.command"), id }, {
        timeout = 20,
        on_exit = function(r)
          if r.code == 0 then
            ranma.notify(first_line(r.stdout) ~= "" and first_line(r.stdout) or ("sent to " .. id))
          else
            ranma.toast("kizuna send: " .. first_line(r.error or (r.stderr ~= "" and r.stderr) or ("exit " .. tostring(r.code))),
              { urgent = true })
          end
        end,
      })
    end,
  }
end

local function actions(peer)
  local items = {}
  local p = pane_of(peer)
  if p then
    items[#items + 1] = { label = "focus its pane", detail = "pane " .. p.id, run = function() p:focus() end }
  end
  if peer.lead and state.by_id[peer.lead] then
    -- kizuna refuses mail for a worker whose lead runs: the lead owns the work.
    items[#items + 1] = { label = "message its lead", detail = peer.lead, run = function() send(peer.lead) end }
    items[#items + 1] = { label = "message this worker anyway", detail = "--worker",
                          run = function() send(peer.id, true) end }
  else
    items[#items + 1] = { label = "message it", detail = "kizuna send", run = function() send(peer.id) end }
  end
  items[#items + 1] = { label = "copy its id", detail = peer.id, run = function()
    ranma.copy(peer.id)
    ranma.notify("copied " .. peer.id)
  end }
  ranma.picker {
    title = peer.id,
    items = items,
    on_select = function(item) item.run() end,
  }
end

local function open()
  if state.missing then return ranma.notify("kizuna is not installed here") end
  if not state.loaded then
    poll()
    return ranma.notify("kizuna: still looking for agents")
  end
  if #state.peers == 0 then return ranma.notify("kizuna: no agents running") end
  local items = {}
  for _, peer in ipairs(state.peers) do
    local home = (os.getenv("HOME") or "~"):gsub("%p", "%%%0")
    local where = peer.repo or (peer.folder or "?"):gsub("^" .. home, "~")
    -- ranma's picker is at most 72 cells, and draws a detail only where it
    -- fits beside the whole label (it never cuts one): the label is cut here
    -- so the state and role always show.
    if peer.branch then
      where = where .. " (" .. peer.branch .. (peer.worktree and ", worktree" or "") .. ")"
    end
    local detail = { peer.state or (peer.headless and "headless") or "—" }
    detail[#detail + 1] = role_of(peer)
    detail[#detail + 1] = not pane_of(peer) and "no pane here" or nil
    local text = table.concat(detail, "  ")
    local label = (peer.profile or peer.provider or "?") .. " · " .. where
      .. (peer.title and (" · " .. peer.title) or "")
    items[#items + 1] = { label = fit(label, PICKER - width(text)), detail = text, peer = peer }
  end
  local n, idle = counts()
  ranma.picker {
    title = "kizuna · " .. n .. (n == 1 and " agent" or " agents") .. ", " .. idle .. " idle",
    items = items,
    on_select = function(item) actions(item.peer) end,
  }
end

ranma.module("kizuna", {
  interval = 2,
  render = function()
    if state.missing or not state.loaded then return nil end
    local n, idle, busy, waiting = counts()
    if n == 0 then return { text = "no agents", style = "dim" } end
    return {
      text = n .. (n == 1 and " agent" or " agents") .. " · " .. idle .. " idle"
        .. (waiting > 0 and (" · " .. waiting .. " waiting") or ""),
      style = waiting > 0 and "urgent" or busy > 0 and "accent" or "dim",
    }
  end,
  on_click = open,
})

ranma.command("kizuna", function() open() end, { desc = "kizuna's agents: focus one or message it" })
ranma.command("kizuna-send", function(id)
  if not id or id == "" then return open() end
  local peer = state.by_id[id]
  if peer and peer.lead and state.by_id[peer.lead] then
    return ranma.notify(id .. " is a worker of " .. peer.lead .. ": message the lead (:kizuna to send anyway)")
  end
  send(id)
end, {
  desc = "message one of kizuna's agents",
  args = "<id>",
  complete = function()
    local ids = {}
    for _, peer in ipairs(state.peers) do ids[#ids + 1] = peer.id end
    return ids
  end,
})
ranma.on("user:kizuna_open", function() open() end)

-- The badges follow a change in the panel at once, not at the next look.
ranma.on("option_change", function(e)
  if e.key == "kizuna.badges" or e.key == "kizuna.badge_state" or e.key == "agents.badges" then badge_all() end
end)

-- A tick a second that looks when kizuna.poll has passed: the option is read
-- as it is now, so init.lua and the settings panel set it after this loads.
local last = 0
timer = ranma.every(1000, function()
  if os.time() - last >= ranma.get("kizuna.poll") then
    last = os.time()
    poll()
  end
end)
ranma.defer(0, function() last = os.time(); poll() end)
