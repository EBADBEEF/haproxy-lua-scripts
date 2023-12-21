local function log(lvl, ...)
    core.log(lvl, "auth:" .. string.format(...))
    print("auth: " .. string.format(...))
end
local function err(...) log(core.err, ...) end
local function dbg(...) log(core.debug, ...) end
local function info(...) log(core.info, ...) end
local function notice(...) log(core.notice, ...) end

local sessions = { }

local function print_login_html()
  return string.format([[
  <link rel="icon" href="data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA=">
  <form method="POST" enctype="custom/login" >
  <input type="password" name="password" value="" />
  <input type="submit" name="login" value="Login" />
  </form>
  ]])
end

local function auth_login_svc(http)
  dbg("in auth_login http.path=%s", http.path)
  local login_html = print_login_html()
  local status = 401
  http:set_status(status)
  http:add_header("content-length", string.len(login_html))
  http:add_header("content-type", "text/html")
  http:start_response()
  if http.method ~= "HEAD" then
    http:send(login_html)
  end
end

local function parse_login_form(txn, form)
  dbg("parse_login_form: %s [[ %s ]] ", form, txn.sc:url_dec(form))
  local t = {}
  for param in string.gmatch(form, "[?&]?([^&]+)") do
    for k, v in string.gmatch(param, "(%w+)=(%w+)") do
      --dbg("form param %s = %s", k, v)
      k = txn.sc:url_dec(k)
      v = txn.sc:url_dec(v)
      t[k] = v
    end
  end
  return t
end

local function validate_login_form(txn, params)
  local cookie_name = txn:get_var("req.cookie_name")
  local cookie_domain = txn:get_var("req.cookie_domain")
  local password = txn:get_var("req.password")
  if cookie_name == nil then
    err("could not find req.cookie_name")
    return act.ERROR
  end
  if password == nil then
    err("could not find req.password")
    return act.ERROR
  end
  if params["password"] == password then
    local uuid = txn.sf:uuid(4)
    local cookie_string = string.format('%s=%s', cookie_name, uuid)
    sessions[uuid] = true -- todo: timestamp, client info, anything that if it changes client needs to login
    if cookie_domain ~= nil then
      cookie_string = cookie_string .. string.format("; Domain=%s", cookie_domain)
    end
    dbg("login post good, set-cookie %s", cookie_string)
    return cookie_string
  end
  dbg("login bad (password was %s)", params["password"])
  return nil
end

local function auth_request(txn)
  local method = txn.sf:method()
  local path = txn.sf:path()
  local content_type = txn.sf:req_hdr("content-type")
  dbg(">>> REQ %s %s", method, path)

  if method == "POST" and content_type == "application/x-www-form-urlencoded" then
    local data = txn.sf:req_body()
    local form = parse_login_form(txn, data)
    local setcookie = validate_login_form(txn, form)
    if setcookie ~= nil then
      txn:set_var("req.setcookie", setcookie)
      txn:set_var("req.location", "//"..txn.sf:hdr("host")..txn.sf:path())
    end
    --txn.http:req_set_method("GET")
    return act.CONTINUE
  end

  -- read session token from cookie or header
  local cookie_name = txn:get_var("req.cookie_name")
  local uuid = txn.sf:req_cook(cookie_name)
  if uuid == "" then
    uuid = txn.sf:req_hdr(cookie_name)
  end

  -- check if session token is in our sessions table
  if uuid ~= nil and sessions[uuid] ~= nil then
    dbg(string.format("in auth_request, found uuid=%s", uuid))
    txn:set_var('req.allow', true)
  end

  return act.CONTINUE
end

core.register_service("auth-login-inline", 'http', auth_login_svc)
core.register_action("auth-inline", { 'http-req' }, auth_request, 0)
core.log(core.alert, string.format("auth-inline.lua: loaded"))
