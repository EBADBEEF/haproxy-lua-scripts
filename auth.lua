-- global variable
auth_lua_loaded = false

local socket = require("socket")

-- some convenience logging functions
local function log(lvl, ...)
    core.log(lvl, "auth:" .. string.format(...))
    print("auth: " .. string.format(...))
end
local function dbg(...) log(core.debug, ...) end
local function info(...) log(core.info, ...) end
local function notice(...) log(core.notice, ...) end

--global in-memory session table
local sessions = {
  joe = "a timestamp eventually",
}

local cookie_name = "rodeo"

local loginPage = [[
<link rel="icon" href="data:image/gif;base64,R0lGODlhAQABAAAAACwAAAAAAQABAAA=">
<form method="POST" action="/login">
<input type="text" name="user" value="cow" />
<input type="password" name="password" value="" />
<input type="submit" name="login" value="Login" />
</form>
]]

--if http.headers["content-type"][0] ~= "application/x-www-form-urlencoded" then
--  print("error")
--end
--first, split on ?&
--second, split on =
--third, url_dec? *shrug*
-- maybe swap 3rd and 2nd

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
  if params["password"] == "SomewhereOverTheRainbow" then
    local uuid=http.sf:uuid(4)
    --local domain=';domain=.dev.ebadf.com'
    local domain=""
    dbg("found match, set-cookie", string.format('%s=%s',cookie_name, uuid)..domain)
    -- todo: timestamp, client info, anything that if it changes client needs to login
    sessions[uuid] = true
    http:add_header("set-cookie", string.format('%s=%s',cookie_name, uuid))
  end
end

local function auth_login(http)
  dbg("login",http.method,http.path)
  local expected_login = false
  local status = 401
  if string.find(http.path, "^/login") then
    expected_login = true
    status = 200
  end
  if http.method == "POST" and expected_login then
    local location = "/"
    local data = http:receive()
    local params = parse_login_form(http, data)
    validate_login_form(http, params)
    http:set_status(302)
    http:add_header("location", location)
    http:start_response()
  else
    http:set_status(status)
    http:add_header("content-length", string.len(loginPage))
    http:add_header("content-type", "text/html")
    http:start_response()
    if http.method ~= "HEAD" then
      http:send(loginPage)
    end
  end
end

local function auth_request(txn)
  local uuid = txn.sf:req_cook(cookie_name)
  if uuid == "" then
    uuid = txn.sf:req_hdr(cookie_name)
  end
  dbg(string.format("in auth_request, uuid=%s", uuid))
  if uuid ~= nil and sessions[uuid] ~= nil then
    dbg("found uuid")
    txn:set_var('txn.allow', true)
  end
  return act.CONTINUE
end

core.register_action("auth", { 'http-req' }, auth_request, 0)
core.register_service("login", 'http', auth_login)
if not auth_lua_loaded then
  core.log(core.alert, string.format("auth.lua: loaded"))
  auth_lua_loaded = true
end
