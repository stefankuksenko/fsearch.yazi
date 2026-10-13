--- @since 26.9.1

-- Search names below the current folder with fsearch (github.com/noahdunnagan/fsearch) instead of fd.
-- fsearch answers from its index of the full disk in milliseconds; fd reads every folder first.
-- One typed word is a regex on the name, as with fd. With several words, each word must be in the
-- path below the folder, in any order, and one of them in the name: `invoice 2025` finds
-- `2025/invoice-march.pdf`. The result is Yazi's usual search view, and it changes while
-- the text is typed.

local M = {}

-- fsearch returns no more names than this. A list of this size is not complete.
local LIMIT = 100000
-- The limit for the list that changes while the text is typed. Return gives the full list.
local LIVE_LIMIT = 1000

local tab = ya.sync(function()
  return cx.active.current.cwd, cx.active.pref.show_hidden
end)

-- fsearch indexes the start disk only, so fd must search each other volume (a USB disk, a disk
-- image). This gives the mount points of such volumes below the folder. It leaves out /dev and
-- /System/Volumes: macOS keeps its own volumes there, and the data volume, which is below `/` too.
-- The result is nil when fd must do the full search:
-- - fsearch is not on this Mac;
-- - its daemon runs without Full Disk Access, and then it skips Desktop, Documents, Downloads and
--   the cloud folders;
-- - the folder is a link, for which fsearch gives the real paths;
-- - the folder is on another volume.
local function other_volumes(root, prefix)
  if root:find('"', 1, true) then
    return nil -- fsearch has no way to write a `"` inside a quoted value
  end
  local status = Command("fsearch"):arg("status"):output()
  if not status or not status.stdout:find('"full_disk_access":true', 1, true) then
    return nil
  end
  local first = Command("fsearch"):arg({ '"in:' .. root .. '"', "limit:1" }):output()
  if first.stdout:sub(1, #prefix) ~= prefix then
    return nil
  end
  local below = {}
  for point in Command("/sbin/mount"):output().stdout:gmatch(" on (.-) %(") do
    if point == "/" then
      -- the start disk
    elseif (root .. "/"):sub(1, #point + 1) == point .. "/" then
      return nil
    elseif point:sub(1, #prefix) == prefix and point ~= "/dev" and point:sub(1, 16) ~= "/System/Volumes/" then
      below[#below + 1] = point
    end
  end
  return below
end

-- A name can store й and ё as two characters (the letter and its mark). Match both forms, as Yazi
-- does for fd. Inside a `[...]` class the group has no meaning, so such a pattern stays as it is.
local function both_forms(pattern)
  if pattern:find("[", 1, true) then
    return pattern
  end
  for letter, forms in pairs {
    ["й"] = "(?:й|и\u{306})",
    ["Й"] = "(?:й|и\u{306})",
    ["ё"] = "(?:ё|е\u{308})",
    ["Ё"] = "(?:ё|е\u{308})",
  } do
    pattern = pattern:gsub(letter, forms)
  end
  return pattern
end

-- Each order of the words, with any text between them. The regex of fsearch has no "and".
local function orders(words)
  if #words == 1 then
    return { words[1] }
  end
  local all = {}
  for i, word in ipairs(words) do
    local rest = {}
    for j, other in ipairs(words) do
      if j ~= i then
        rest[#rest + 1] = other
      end
    end
    for _, tail in ipairs(orders(rest)) do
      all[#all + 1] = word .. ".*" .. tail
    end
  end
  return all
end

-- With hidden files off, fd skips each name that starts with a dot, and all below such a folder.
local function is_hidden(rel)
  return rel:sub(1, 1) == "." or rel:find("/.", 1, true) ~= nil
end

local function notify(content, level)
  ya.notify { title = "Search", content = content, level = level, timeout = 8 }
end

-- The regex for the name and the regex for the path, for the typed text. The name must match one
-- of the words. With more than one word, the path below the folder must match them all.
-- Without a result, the second value is the number of words: none, or more than 5.
local function regexes(text, prefix)
  local words = {}
  for word in both_forms(text):gmatch("%S+") do
    words[#words + 1] = "(?:" .. word .. ")"
  end
  if #words == 0 or #words > 5 then
    return nil, #words
  end
  local name = table.concat(words, "|")
  local below = "^" .. prefix:gsub("[%^%$%(%)%.%[%]%*%+%?%{%}%|\\]", "\\%0")
  return name, #words > 1 and below .. ".*(?:" .. table.concat(orders(words), "|") .. ")"
end

-- The names that fsearch finds, as paths below the folder. Without a result, the second value is
-- the error text, for example for a regex that is not valid.
local function find(root, prefix, name, path, limit)
  -- fsearch joins its arguments and splits them at spaces outside double quotes. Each value is in
  -- quotes, so no typed character has a meaning in the query language of fsearch.
  local args = { '"re:' .. name:gsub('"', "\\x22") .. '"', '"in:' .. root .. '"', "limit:" .. limit }
  if path then
    args[#args + 1] = '"path:' .. path:gsub('"', "\\x22") .. '"'
  end
  local output, err = Command("fsearch"):arg(args):output()
  if not output then
    return nil, "fsearch did not start: " .. tostring(err)
  elseif not output.status.success then
    return nil, (output.stderr:gsub("%s+$", ""))
  end
  local rels = {}
  for line in output.stdout:gmatch("[^\n]+") do
    rels[#rels + 1] = line:sub(#prefix + 1)
  end
  return rels
end

-- Open the search view for the text and fill it in parts, with the same calls as Yazi's own search.
-- The view opens when the first part is ready, so the list does not flash while the text is typed.
local function show(root, text, rels)
  local search = Url(root):into_search(text)
  local id = ya.id("ft")
  local function open()
    ya.emit("cd", { Url(search), source = "search" })
    ya.emit("update_files", { op = fs.op("part", { id = id, url = Url(search), files = {} }) })
  end

  local files, opened = {}, false
  for i, rel in ipairs(rels) do
    local url = search:join(rel)
    local cha = fs.cha(url, true) or fs.cha(url, false) -- the second one is for a link to nothing
    if cha then
      files[#files + 1] = File { url = url, cha = cha }
    end
    if #files == 5000 or i == #rels then
      opened = opened or open() or true
      ya.emit("update_files", { op = fs.op("part", { id = id, url = Url(search), files = files }) })
      files = {}
    end
  end
  opened = opened or open()
  local dir = File { url = search, cha = Cha { mode = tonumber("100644", 8) } }
  ya.emit("update_files", { op = fs.op("done", { id = id, file = dir }) })
end

function M:entry()
  local cwd, show_hidden = tab()
  local root = tostring(cwd.path)
  local prefix = root == "/" and "/" or root .. "/"
  local volumes = other_volumes(root, prefix)
  if not volumes then
    return ya.emit("search", { via = "fd" })
  end

  local function visible(rels)
    local seen, out = {}, {}
    for _, rel in ipairs(rels) do
      if not seen[rel] and (show_hidden or not is_hidden(rel)) then
        seen[rel] = true
        out[#out + 1] = rel
      end
    end
    return out
  end

  -- The mirror of Yazi's prompts at the top (top-center, y = 2): the list changes while the text is
  -- typed, and a prompt at the top hides its first names.
  local input = ya.input {
    title = "Search via fsearch:",
    pos = { "bottom-center", y = -2, w = 50 },
    realtime = true,
    debounce = 0.1,
  }
  -- The text of the list that is on the screen, and whether that list has all names.
  local shown, complete
  local function back()
    if shown then
      ya.emit("cd", { Url(cwd), source = cwd.spec.is_search and "search" or "escape" })
    end
  end

  while true do
    local text, event = input:recv()
    local name, path = regexes(text or "", prefix)

    if event == 3 then
      -- While the text is typed: a short list, and no notice for a regex that is not complete.
      local rels = name and find(root, prefix, name, path, LIVE_LIMIT)
      if rels then
        show(root, text, visible(rels))
        shown, complete = text, #rels < LIVE_LIMIT and #volumes == 0
      end
    elseif event ~= 1 or (not name and path == 0) then
      return back() -- Escape, or Return with no text
    elseif not name then
      back()
      return notify("Type 5 words at most.", "warn")
    elseif shown == text and complete then
      return
    else
      local rels, err = find(root, prefix, name, path, LIMIT)
      if not rels then
        back()
        return notify(err, "error")
      end
      local total = #rels
      -- fd with the rules of fsearch: no letter case, and no skip of git-ignored files.
      for _, point in ipairs(volumes) do
        local found = Command("fd")
          :arg({ "--base-directory", point, "--regex", "--ignore-case", "--no-ignore", "--hidden" })
          :arg(path and { "--full-path", path } or name)
          :output()
        for line in found.stdout:gmatch("[^\n]+") do
          rels[#rels + 1] = point:sub(#prefix + 1) .. "/" .. line:gsub("/$", "")
        end
      end
      show(root, text, visible(rels))
      if total >= LIMIT then
        notify(string.format("More than %d names match. The list is not complete: type a longer word.", LIMIT), "warn")
      end
      return
    end
  end
end

return M
