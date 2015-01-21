-- Render a textfile.
-- @module textfile
-- @author Eduardo Tongson <propolice@gmail.com>
-- @license MIT <http://opensource.org/licenses/MIT>
-- @added 0.9.0

local Str = {}
Str.textfile_render_ok = "textfile.render: Successfully rendered textfile."
Str.textfile_render_skip = "textfile.render: Not overwriting existing destination."
Str.textfile_render_fail = "textfile.render: Error rendering textfile. Error: "
Str.textfile_render_missingsrc = "textfile.render: Can't access or missing source file."
Str.textfile_render_missinglua = "textfile.render: Can't access or missing lua file."
Str.textfile_insert_line_ok = "textfile.insert_line: Successfully inserted line."
Str.textfile_insert_line_skip = "textfile.insert_line: Insert cancelled, found a matching line."
Str.textfile_insert_line_fail = "textfile.insert_line: Error inserting line."
Str.textfile_remove_line_ok = "textfile.remove_line: Successfully removed line."
Str.textfile_remove_line_fail = "textfile.remove_line: Error removing line."
Str.textfile_missing = "textfile: Can't access or missing file."
local Lua = {
  load = load,
  tonumber = tonumber,
  concat = table.concat,
  insert = table.insert,
  tmpname = os.tmpname,
  rename = os.rename,
  remove = os.remove,
  find = string.find,
  match = string.match,
  require = require
}
local Configi = require"configi"
local Lc = require"cimicida"
local Lustache = require"lustache"
local Pstat = require"posix.sys.stat"
local Px = require"px"
local Cmd = Px.cmd
local textfile = {}
local ENV = {}
_ENV = ENV

local main = function (S, M, G)
  local C = Configi.start(S, M, G)
  C.required = { "path" }
  C.alias.src = { "template" }
  C.alias.path = { "dest", "file", "textfile" }
  C.alias.lua = { "data" }
  C.alias.table = { "view" }
  C.alias.line = { "text" }
  C.alias.pattern = { "match" }
  return Configi.finish(C)
end

local write = function (F, P, R)
  -- ignore P.diff if diffutils is not found
  if not Px.binpath("diff") then P.diff = false end
  if (P.debug or P.test) and (P.diff) then
    local temp = Lua.tmpname()
    if Px.awrite(temp, P._input, 384) then
      local dtbl = {}
      local res, _, diff = Cmd["/usr/bin/diff"]{ "-N", "-a", "-u", P.path, temp }
      Lua.remove(temp)
      if res then
        F.msg(P.path, "No changes found", nil, 0)
        R.notify_kept = P.notify_kept
        R.kept = true
        return R
      else
        for n = 1, #diff.stdout do
          dtbl[n] = Lua.match(diff.stdout[n], "[%g%s]+") or ""
        end
        F.msg(P.path, "Showing changes", true, 0, Lc.strf("Diff:%s%s%s", "\n\n", Lua.concat(dtbl, "\n"), "\n"))
      end
    end
  end
  if F.run(Px.awrite, P.path, P._input, P.mode) then
    F.msg(P.path, Str.textfile_render_ok, true)
    R.notify = P.notify
    R.repaired = true
  else
    F.msg(P.path, Str.textfile_render_fail, false)
    R.notify_failed = P.notify_failed
    R.failed = true
  end
  return R
end

--- Render a textfile using Lustache.
-- <br />
-- See: <https://github.com/Olivine-Labs/lustache>
-- @note Requires the diffutils package for the diff parameter to work
-- @param path output file [REQUIRED] [ALIAS: dest,file,textfile]
-- @param src source template [REQUIRED] [ALIAS: template]
-- @param table [REQUIRED] [ALIAS: view]
-- @param lua [ALIAS: data]
-- @param mode mode bits for output file [DEFAULT: "0600"]
-- @param diff show diff [CHOICES: "yes","no"]
-- @param force overwrite existing file [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @usage textfile.render [[
--   template "/etc/something/config.template"
--   dest "/etc/something/config"
--   view "view_model"
--   data "/etc/something/config.lua"
--   force "true"
-- ]]
function textfile.render (S)
  local M = { "src", "force", "lua", "table", "mode", "diff" }
  local F, P, R = main(S, M)
  P.mode = P.mode or "0600"
  P.mode = Lua.tonumber(P.mode, 8)
  if Pstat.stat(P.path) and not P.force then
    F.msg(P.path, Str.textfile_render_skip, nil)
    R.notify_kept = P.notify_kept
    return R
  end
  local ti = F.open(P.src)
  if not ti then
    F.msg(P.src, Str.textfile_render_missingsrc, false)
    R.notify_failed = P.notify_failed
    R.failed = true
    return R
  end
  local lua = F.open(P.lua)
  if not lua then
    F.msg(P.lua, Str.textfile_render_missinglua, false)
    R.notify_failed = P.notify_failed
    R.failed = true
    return R
  end
  local env = { require = Lua.require }
  local tbl
  local chunk, err = Lua.load(lua, lua, "t", env)
  if chunk then
    chunk()
    tbl = env[P.table]
  else
    F.msg(P.src, err, false)
    R.notify_failed = P.notify_failed
    R.failed = true
    return R
  end
  P._input = Lustache:render(ti, tbl)
  return write(F, P, R)
end

--- Insert lines into an existing file.
-- @param path path of textfile to modify [REQUIRED] [ALIAS: dest,file,textfile]
-- @param line text to insert [REQUIRED] [ALIAS: text]
-- @param inserts a line (string) if found, skips the operation
-- @param pattern line is added before or after this pattern [ALIAS: match]
-- @param plain turn off pattern matching facilities [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @param before [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @param after [CHOICES: "yes","no"] [DEFAULT: "yes"]
-- @usage textfile.insert_line [[
--   path "/etc/sysctl.conf"
--   pattern "# http://cr.yp.to/syncookies.html"
--   text "net.ipv4.tcp_syncookies = 1"
--   after "true"
--   plain "true"
-- ]]
function textfile.insert_line (S)
  local M = { "diff", "line", "plain", "pattern", "before", "after", "inserts" }
  local F, P, R = main(S, M)
  P.mode = Pstat.stat(P.path).st_mode
  local file = Lc.file2tbl(P.path)
  if not file then
    F.msg(P.path, Str.textfile_missing, false, 0)
    R.failed = true
    R.notify_failed = P.notify_failed
    return R
  end
  if P.inserts then
    if Lc.tfind(file, P.inserts) then
      F.msg(P.line, Str.textfile_insert_line_skip, nil, 0)
      R.kept = true
      R.notify_kept = P.notify_kept
      return R
    end
  end
  if not P.pattern then
    if Lc.tfind(file, P.line) then
      F.msg(P.line, Str.textfile_insert_line_skip, nil, 0)
      R.kept = true
      R.notify_kept = P.notify_kept
      return R
    else
      file[#file + 1] = P.line .. "\n"
    end
  else
    local x, n, nf = 1, 1, #file
    if P.before then -- after "yes" is default
      x = 0
    end
    repeat
      if Lua.find(file[n], P.pattern, 1, P.plain) then
        Lua.insert(file, n + x, P.line .. "\n")
        nf = nf + 1
        n = n + 2
      else
        n = n + 1
      end
    until n == nf
  end
  P._input = Lua.concat(file)
  return write(F, P, R)
end

--- Remove lines from an existing file.
-- @param path path of textfile to modify [REQUIRED] [ALIAS: dest,file,textfile]
-- @param pattern text pattern to remove [REQUIRED] [ALIAS: match]
-- @param plain turn off pattern matching facilities [CHOICES: "yes","no"] [DEFAULT: "no"]
-- @usage textfile.remove_line [[
--   path "/etc/sysctl.conf"
--   match "net.ipv4.ip_forward = 1"
--   plain "true"
-- ]]
function textfile.remove_line (S)
  local M = { "pattern", "plain", "diff" }
  local F, P, R = main(S, M)
  P.mode = Pstat.stat(P.path).st_mode
  local file = Lc.file2tbl(P.path)
  if not file then
    F.msg(P.path, Str.textfile_missing, false, 0)
    R.notify_failed = P.notify_failed
    R.failed = true
    return R
  end
  P._input = Lua.concat(Lc.filtertval(file, P.pattern, P.plain))
  return write(F, P, R)
end

return textfile
