local type, pcall, next, setmetatable, require, tostring =
  type, pcall, next, setmetatable, require, tostring
local string = string
local Psyslog = require"posix.syslog"
local Psystime = require"posix.sys.time"
local stat = require"posix.sys.stat"
local lib = require"lib"
local time, fmt, table, util, exec, path, os =
  lib.time, lib.fmt, lib.table, lib.util, lib.exec, lib.path, lib.os
local strings = require"cfg-core.strings"
local std = require"cfg-core.std"
local args = require"cfg-core.args"
local cfg = {}
local _, policy = pcall(require, "cfg-policy")
_ = nil
_ENV = nil

--[[ Module internal functions ]]
local Lmod = {}

--- Return a function that passes the string argument to syslog() and add it to tbl
-- It calls string.format if a C-like argument is passed to the returned function
-- @param T module table (TABLE)
-- @return function (FUNCTION)
function Lmod.dmsg (C)
  return function (item, flag, bool, sec, extra)
    local level, msg
    item = string.match(item, "([%S+]+)")
    if flag == true then
      flag = " OK "
      msg = C.report.repaired
    elseif flag == false then
      flag = "PASS"
      msg = C.report.kept
    elseif flag == nil then
      flag = "FAIL"
      msg = C.report.failed
      level = Psyslog.LOG_ERR
    elseif type(flag) == "string" then
      msg = flag
      if bool == true then
        flag = " OK "
      elseif bool == nil then
        level = Psyslog.LOG_ERR
        flag = "FAIL"
      elseif bool == false then
        flag = "PASS"
      else
        flag = "INFO"
      end
    end
    local str
    if sec == nil then
      str = string.format([[

 [%s] %s
    Comment: %s
    Subject: %s
    %s%s]],
    flag, msg, C.parameters.comment, item or "", extra or "", "\n")
    else
       str = string.format([[

 [%s] %s
    Elapsed: %.fs
    %s%s]],
    flag, msg, sec, extra or "", "\n")
    end
    local rs = strings.rs
    local lstr
    sec = sec or ""
    if string.len(C.parameters.comment) > 0 then
      lstr = string.format("[%s]%s%s%s%s%s%s%s#%s", flag, rs, msg, rs, item, rs, sec, rs, C.parameters.comment)
    else
      lstr = string.format("[%s]%s%s%s%s%s%s", flag, rs, msg, rs, item, rs, sec)
    end
    std.log(args["s"], args["l"], lstr, level)
    C.results.msgt[#C.results.msgt + 1] = {
      item = item,
      msg = msg,
      elapsed = sec,
      comment = C.parameters.comment,
      result = flag,
    }
    C.results.msg[#C.results.msg + 1] = str .. "\n"
  end
end

function Lmod.msg (C)
  return function (item, flag, bool)
    local level, msg, lf
    item = string.match(item, "([%S+]+)")
    if flag == true then
      flag = "\27[1;32m".."[ OK ]".."\27[0m"
      lf =  "OK."
      msg = C.report.repaired
    elseif flag == false then
      flag = "\27[1;33m".."[PASS]".."\27[0m"
      lf = "PASS."
      msg = C.report.kept
    elseif flag == nil then
      flag = "\27[1;31m".."[FAIL]".."\27[0m"
      lf = "FAIL."
      msg = C.report.failed
      level = Psyslog.LOG_ERR
    elseif type(flag) == "string" then
      msg = flag
      if bool == true then
        flag = "\27[1;32m".."[ OK ]".."\27[0m"
        lf =  "OK."
      elseif bool == nil then
        level = Psyslog.LOG_ERR
        flag = "\27[1;31m".."[FAIL]".."\27[0m"
        lf = "FAIL."
      elseif bool == false then
        flag = "\27[1;33m".."[PASS]".."\27[0m"
        lf = "PASS."
      else
        flag = "\27[1;34m".."[INFO]".."\27[0m"
        lf = "INFO."
      end
    end
    local rs = strings.rs
    local lstr, llstr
    if string.len(C.parameters.comment) > 0 then
      lstr = string.format("%s%s%s%s%s%s#%s", flag, rs, msg, rs, item, rs, C.parameters.comment)
      llstr = string.format("%s%s%s%s%s%s#%s", lf, rs, msg, rs, item, rs, C.parameters.comment)
    else
      lstr = string.format("%s%s%s%s%s", flag, rs, msg, rs, item)
      llstr = string.format("%s%s%s%s%s", lf, rs, msg, rs, item)
    end
    std.log(args["s"], args["l"], llstr, level)
    C.results.msgt[#C.results.msgt + 1] = {
      item = item,
      msg = msg,
      comment = C.parameters.comment,
      result = flag
    }
    C.results.msg[#C.results.msg + 1] = lstr
  end
end

--- Check if a required parameter is set.
-- Produce an error (exit code 1) if a required parameter is missing.
-- @param T main table (TABLE)
function Lmod.required (C)
  for n = 1, #C._required do
    if not C.parameters[C._required[n]] then
      fmt.panic("%s Required parameter '%s' missing.\n", strings.SERR, C._required[n])
    end
  end
end

-- Warn (stderr output) if a "module.function" parameter is ignored.
-- @param T main table (TABLE)
function Lmod.ignoredwarn (C)
  for n = 1, #C._required do C._module[#C._module + 1] = C._required[n] end -- add C.required to M
  -- Core parameters are added as valid parameters
  C._module[#C._module + 1] = "comment"
  C._module[#C._module + 1] = "handle"
  C._module[#C._module + 1] = "register"
  C._module[#C._module + 1] = "context"
  C._module[#C._module + 1] = "notify"
  C._module[#C._module + 1] = "notify_failed"
  C._module[#C._module + 1] = "notify_kept"
  C._module[#C._module + 1] = "require"
  C._module[#C._module + 1] = "before"
  C._module[#C._module + 1] = "creates"
  C._module[#C._module + 1] = "installs" -- alias to creates
  C._module[#C._module + 1] = "removes"
  C._module[#C._module + 1] = "uninstalls" -- alias to removes
  -- Now check for any undeclared _module parameter
  local Ps = table.to_hash(C._module, 0)
  for param, _ in next, C.parameters do
    if Ps[param] == nil then
      fmt.warn("%s Parameter '%s' ignored.\n", strings.WARN, param)
    end
  end
end

--- Process a promise.
-- 1. Fill environment with functions to assign parameters
-- 2. Load promise chunk
-- 3. Check for required parameter(s)
-- 4. Debugging
-- @return functions table
-- @return parameters table
-- @return results table
function cfg.init(P, M)
  local C = {
      _module = M.parameters or {},
       report = M.report, -- cannot be unset
      _required = M.required or {},
      functions = {},
     parameters = P,
      results = { kept = false, repaired = false, failed = false, msg = {}, msgt = {} }
  }
  local creates = P.creates or P.installs
  if creates and stat.stat(creates) then
    C.results.kept = true
  end
  local removes = P.removes or P.uninstalls
  if removes and not stat.stat(removes) then
    C.results.kept = true
  end
  -- assign aliases
  local _temp = {}
  if pcall(next, M.alias) then
    for param, aliases in next, M.alias do
      for n = 1, #aliases do
        _temp[aliases[n]] = param
      end
    end
    -- Preset found aliases to true since it's not ok to iterate and add at the same time.
    for alias, param in next, _temp do
      if C.parameters[alias] then
        C.parameters[param] = true
      end
    end
  end
  -- assign values
  for p, v in next, C.parameters do
    if _temp[p] then
      -- remove alias so it won't warn about an ignored parameter
      C.parameters[p] = nil
      -- reuse and update p for each alias hit
      p = _temp[p]
    end
    if util.truthy(v) then
      C.parameters[p] = true
    elseif util.falsy(v) then
      C.parameters[p] = false
    else
      C.parameters[p] = v
    end
  end
  -- Check for required parameters
  Lmod.required(C)
  -- Return an F.run() depending on debug, test flags
  C.parameters.comment = C.parameters.comment or ""
  local msg
  local functime = function (f, ...)
    local t1 = Psystime.gettimeofday()
    local stdout, stderr = "", ""
    local ok, rt = f(...)
    local err
    if rt then
      err = exec.exit_string(rt.exe, rt.status, rt.code)
      if type(rt.stdout) == "table" then
        stdout = table.concat(rt.stdout, "\n")
      end
      if type(rt.stderr) == "table" then
        stderr = table.concat(rt.stderr, "\n")
      end
    else
      err = "Successful execution."
    end
    local secs = time.diff(Psystime.gettimeofday(), t1)
      secs = string.format("%s.%s", tostring(secs.sec), tostring(secs.usec))
      msg(strings.EXEC, err, ok, secs,
        string.format("stdout:\n%s\n    stderr:\n%s\n", stdout, stderr))
      return ok, rt
  end -- functime()
  if args["x"] then
    msg = Lmod.msg(C)
    C.functions.run = function (f, ...)
      local ok, rt = f(...)
      local err
      if rt then
        err = exec.exit_string(rt.exe, rt.status, rt.code)
      else
        err = "Successful execution."
      end
      msg(strings.EXEC, err, ok)
      return ok, rt
    end -- F.run()
  elseif args["t"] or args["v"] then
    msg = Lmod.dmsg(C)
    Lmod.ignoredwarn(C) -- Warn for ignored parameters
  else
    msg = Lmod.msg(C)
    C.functions.run = function(f, ...)
      local ok, rt = f(...)
      return ok, rt
    end
  end
  if args["t"] then
    C.functions.run = function()
      msg(strings.EXEC, "Test option passed. Noop F.run().", true)
      return true, {stdout = {}, stderr = {}}, true
    end -- F.run()
    C.functions.xrun = functime -- if you must execute something use F.xrun()
  elseif args["v"] then
    C.functions.run = functime -- functime() is used when debug=true
  end
  C.functions.msg = msg -- Assign msg to F.msg()
  C.functions.result = function (item, test, alt)
    local flag
    if test == false then
      flag = false
      C.results.notify_kept = C.parameters.notify_kept
    elseif test then
      flag = true
      C.results.notify = C.parameters.notify
      C.results.repaired = true
    elseif test == nil then
      C.results.notify_failed = C.parameters.notify_failed
      C.results.failed = true
    end
    if type(alt) == "string" then
      msg(item, alt, flag)
    else
      msg(item, flag)
    end
    return C.results
  end -- F.result()
  C.functions.kept = function (item)
    C.results.notify_kept = C.parameters.notify_kept
    msg(item, false)
    return C.results
  end -- F.kept()
  C.functions.open = function (f)
    local file = std.path().."/"..f
    local dir, base, ext = path.decompose(f)
    -- Actual files has priority
    if os.is_file(file) then
       return file.read_to_string(file)
    elseif policy[dir][base] then
       return policy[dir][base]
    else
       fmt.panic("%s %s or %s not found\n", strings.SERR, file, base.."."..ext)
    end
  end

  -- Methods available to P
  local insert_if = function(self, source, target, i)
    i = i or #target
    for k, v in next, source do
      table.insert_if(self[k], target, i, v)
    end
  end
  local set_if_not = function(self, test, value)
    if not self[test] then
      self[test] = value
    end
  end
  local set_if = function(self, test, value)
    if self[test] then
      self[test] = value
    end
  end
  local P_methods = {
    insert_if = insert_if,
    set_if_not = set_if_not,
    set_if = set_if
  }
  setmetatable(C.parameters, { __index = P_methods })
  return C.functions, C.results -- F, R
end

return cfg
