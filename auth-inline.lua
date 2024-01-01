require("io")

-- argv can be used to pass in values from lua-load
local argv = table.pack(...)

local function log(txn, lvl, ...)
    txn:log(lvl, "auth: " .. string.format(...))
    --print("auth: " .. string.format(...))
end
local function err(txn, ...) log(txn, core.err, ...) end
local function dbg(txn, ...) log(txn, core.debug, ...) end
local function info(txn, ...) log(txn, core.info, ...) end
local function notice(txn, ...) log(txn, core.notice, ...) end

local sessions = { }

local function form_to_table(txn, form)
  dbg(txn, "form_to_table: %s [[ %s ]] ", form, txn.sc:url_dec(form))
  local t = {}
  for param in string.gmatch(form, "[?&]?([^&]+)") do
    for k, v in string.gmatch(param, "(%w+)=(%w+)") do
      --dbg(txn, "form param %s = %s", k, v)
      k = txn.sc:url_dec(k)
      v = txn.sc:url_dec(v)
      t[k] = v
    end
  end
  return t
end

local function login_form(txn, setcookie)
  return txn:reply{
    status = 401,
    headers = {
      ["content-type"]  = { "text/html" },
      ["set-cookie"] = { setcookie },
    },
    body = login_page_body,
  }
end

local function successful_login(txn, setcookie)
  -- redirect back to ourself but with auth cookie set
  headers = {
    ["content-type"]  = { "text/html" },
    ["cache-control"] = { "no-cache", "no-store" },
    ["location"] = { "//"..txn.sf:hdr("host")..txn.sf:path() },
  }
  if setcookie ~= nil then
    headers["set-cookie"] = { setcookie }
  end
  return txn:reply{status = 303, headers = headers}
end

local function bake_cookie(name, value, domain)
  local str = string.format('%s=', name)
  if value == nil then
    str = str .. 'invalid; max-age=-1'
    return str
  end
  str = str .. value
  if domain ~= nil then
    str = str .. string.format("; Domain=%s", domain)
  end
  return str
end

local function log_login(txn, success)
  notice(txn, "%s from src=%s path=%s"
    ,success and "success" or "failure"
    ,txn.sf:src()
    ,txn.sf:path()
  )
end

local function auth_request_inline(txn)
  local cookie_name = txn:get_var("req.cookie_name") or "authsession"
  local cookie_domain = txn:get_var("req.cookie_domain")
  local password = txn:get_var("req.password")
  if password == nil then
    err(txn, "could not find req.password")
    return act.ERROR
  end

  -- read session token from cookie or header
  local uuid = txn.sf:req_cook(cookie_name)
  if uuid == "" then
    uuid = txn.sf:req_hdr(cookie_name)
  end

  -- check if session token is in our sessions table
  if uuid ~= nil and sessions[uuid] ~= nil then
    dbg(txn, "logged in (%s)", txn.sf:path())
    return act.CONTINUE
  end

  if txn.sf:method() == "POST" and txn.sf:req_hdr("content-type") == "application/x-www-form-urlencoded" then
    -- reading the body of a request depends on 'http-request wait-for-body ...
    -- if METH_POST' or 'option http-buffer-request'
    local form = form_to_table(txn, txn.sf:req_body())
    if form["password"] ~= nil then
      -- slow down password check to prevent brute forcing
      core.sleep(1)
      if form["password"] == password then
        local uuid = txn.sf:uuid(4)
        sessions[uuid] = true -- todo: timestamp, client info, anything that if it changes client needs to login
        setcookie = bake_cookie(cookie_name, uuid, cookie_domain)
        log_login(txn, true)
        txn:done(successful_login(txn, setcookie))
      else
        log_login(txn, false)
      end
    end
  end

  dbg(txn, "no or invalid session, deleting any existing cookies...")
  txn:done(login_form(txn, bake_cookie(cookie_name, nil, cookie_domain)))
end

core.register_action("auth", { 'http-req' }, auth_request_inline, 0)
core.log(core.alert, string.format("auth.lua: loaded"))

-- global variable for login body, can optionally pass in a filename as the
-- first argument, like 'lua-load auth.lua <filename>'
if argv[1] ~= nil then
login_page_body = io.open(argv[1], "r"):read("*a")
else
login_page_body = [[
<form method="POST">
<input type="normal" name="password" />
<input type="submit" name="login" value="login" />
</form>
]]
end
