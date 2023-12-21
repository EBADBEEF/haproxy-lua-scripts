-- global variable
auth_lua_loaded = false

local socket = require("socket")

-- some convenience logging functions
local function log(lvl, ...)
    core.log(lvl, "auth:" .. string.format(...))
    print("auth: " .. string.format(...))
end
local function err(...) log(core.err, ...) end
local function dbg(...) log(core.debug, ...) end
local function info(...) log(core.info, ...) end
local function notice(...) log(core.notice, ...) end

--global in-memory session table
local sessions = { }

local function print_login_html(post_url)
  local prefix = ""
  if post_url:sub(1,1) ~= "/" then
    prefix = "//"
  end

  return string.format([[
  <link rel="icon" href="data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA=">
  <form method="POST" action="%s">
  <input type="password" name="password" value="" />
  <input type="submit" name="login" value="Login" />
  </form>
  ]], prefix..post_url)
end

local function parse_login_form(http, data)
  dbg("parse_login_form:", data, "[[", http.sc:url_dec(data), "]]")
  local t = {}
  for param in string.gmatch(data, "[?&]([^&]+)") do
    --dbg("form param", param)
    for k, v in string.gmatch(data, "(%w+)=(%w+)") do
      k = http.sc:url_dec(k)
      v = http.sc:url_dec(v)
      t[k] = v
    end
  end
  return t
end

local function validate_login_form(http, params)
  local cookie_name = http:get_var("txn.cookie_name")
  local cookie_domain = http:get_var("txn.cookie_domain")
  local password = http:get_var("txn.password")
  if cookie_name == nil then
    err("could not find txn.cookie_name")
    return act.ERROR
  end
  if password == nil then
    err("could not find txn.password")
    return act.ERROR
  end
  if params["password"] == password then
    local uuid = http.sf:uuid(4)
    local cookie_string = string.format('%s=%s', cookie_name, uuid)
    -- save session
    sessions[uuid] = true -- todo: timestamp, client info, anything that if it changes client needs to login
    -- send cookie
    if cookie_domain ~= nil then
      cookie_string = cookie_string .. string.format("; Domain=%s", cookie_domain)
    end
    dbg("login post good, set-cookie %s", cookie_string)
    http:add_header("set-cookie", cookie_string)
    return true
  end
  dbg("login bad")
  return false
end

local function auth_login(http)
  local post_url = http:get_var("txn.login_location")
  if post_url == nil then
    err("auth_login could not find txn.login_location")
    return act.ERROR
  end

  dbg("in auth_login http.path=%s", http.path)

  -- We either wanted to login or failed to authenticate and must login. Note
  -- we could have been sent here by an unauthenticated post to a different
  -- location, so it is important to check the destination to see how we got
  -- here.
  local expected_login = false
  local status = 401
  if (http.headers["host"][0] == post_url) or (string.find(http.path, "^"..post_url)) then
    expected_login = true
    status = 200
  end

  if http.method == "POST" and expected_login then
    local data = http:receive()
    local form = parse_login_form(http, data)
    if validate_login_form(http, form) == true then
      -- TODO: read from query params if they were sent
      local location = "/"
      http:set_status(302)
      http:add_header("location", location)
      http:start_response()
      return act.DONE
    else
      dbg("bad login post")
    end
    -- fall through
  end

  -- login needed or login failed
  local login_html = print_login_html(post_url)
  http:set_status(status)
  http:add_header("content-length", string.len(login_html))
  http:add_header("content-type", "text/html")
  http:start_response()
  if http.method ~= "HEAD" then
    http:send(login_html)
  end
end

core.register_service("login", 'http', auth_login)

local function auth_request(txn)
  local cookie_name = txn:get_var("txn.cookie_name")
  if cookie_name == nil then
    err("could not find txn.cookie_name")
    return act.ERROR
  end

  -- read session token from cookie or header
  local uuid = txn.sf:req_cook(cookie_name)
  if uuid == "" then
    uuid = txn.sf:req_hdr(cookie_name)
  end

  -- check if session token is in our sessions table
  if uuid ~= nil and sessions[uuid] ~= nil then
    dbg(string.format("in auth_request, found uuid=%s", uuid))
    txn:set_var('txn.allow', true)
  else
    dbg(string.format("in auth_request, no session for uuid=%s", uuid))
  end

  return act.CONTINUE
end

core.register_action("auth", { 'http-req' }, auth_request, 0)

if not auth_lua_loaded then
  core.log(core.alert, string.format("auth.lua: loaded"))
  auth_lua_loaded = true
end
