local login_page_body = [[
<html>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<style>
body {
  background: #505170;
}
.logo {
  margin-left: 20%;
  margin-right: 20%;
  width: 60%;
}
.center {
  margin-left: 5%;
  margin-right: 5%;
  width: 90%;
  font-size: calc(5.5vw);
}
.password {
  background: rgb(116,116,148);
  margin-top: 10%;
  padding: 0.2em;
}
.login {
  background: rgb(86,86,98);
  border-radius: 0.2em;
  margin-top: 1em;
  background: linear-gradient(5deg, rgba(86,86,98,1) 0%, rgba(125,122,139,1) 55%, rgba(158,156,169,1) 100%);
  padding: 0.2em;
}
@media (min-width: 800px) {
  .logo {
    margin-left: 40%;
    margin-right: 40%;
    width: 20%;
  }
  .center {
    margin-left: 30%;
    margin-right: 30%;
    width: 40%;
    font-size: calc(2.2vw);
  }
  .password {
    margin-top: 2%;
  }
}
</style>
<script>
function show(e,b) { e.type = b ? 'text' : 'password'; }
</script>
<link rel="icon" href="data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA=">
<img class="logo" src="data:image/gif;base64,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" />
<form method="POST">
<input class="center password" type="normal" name="password" id="password" onfocus="show(this,true)" onblur="show(this,false)" />
<input class="center login" type="submit" name="login" value="login" />
</form>
</html>
]]

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

local function loglogin(txn, success)
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
    end
    if form["password"] == password then
      local uuid = txn.sf:uuid(4)
      sessions[uuid] = true -- todo: timestamp, client info, anything that if it changes client needs to login
      setcookie = bake_cookie(cookie_name, uuid, cookie_domain)
      loglogin(txn, true)
      txn:done(successful_login(txn, setcookie))
    else
      loglogin(txn, false)
    end
  end

  dbg(txn, "no or invalid session, deleting any existing cookies...")
  txn:done(login_form(txn, bake_cookie(cookie_name, nil, cookie_domain)))
end

core.register_action("auth", { 'http-req' }, auth_request_inline, 0)
core.log(core.alert, string.format("auth.lua: loaded"))

