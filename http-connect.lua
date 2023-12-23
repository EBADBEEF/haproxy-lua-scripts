-- some convenience logging functions
local function log(txn, lvl, ...)
    txn:log(lvl, "http-connect: " .. string.format(...))
    --print("http-connect: " .. string.format(...))
end
local function dbg(txn, ...) log(txn, core.debug, ...) end
local function info(txn, ...) log(txn, core.info, ...) end
local function notice(txn, ...) log(txn, core.notice, ...) end

local function http_connect(txn)
  local data = txn.req:data(0)
  -- read full request
  if data:sub(-4) == "\r\n\r\n" then
    txn.req:remove(0, data:len())
    local target = data:match("CONNECT ([^ ]+)", 1)
    local addr, port = target:lower():match("(.+):([0-9]+)$")
    notice(txn, "%s:%s connect to %s:%s",
        txn.sf:src(), txn.sf:src_port(), addr, port)
    if addr:match("[0-9]+%.[0-9]+%.[0-9]+%.[0-9]") then
      --ipv4 address
    elseif addr:match("[0-9a-f:]+:[0-9a-f:]+") then
      --ipv6 address
    else
      txn:set_var("req.resolvedns", true)
    end
    txn.res:send("HTTP/1.1 200 OK\r\n\r\n")
    txn:set_var("req.dst", addr)
    txn:set_var("req.port", port)
    return act.CONTINUE
  end
  return act.DENY
end

core.register_action("http-connect", { 'tcp-req' }, http_connect, 0)
if core.thread == 1 then
core.log(core.alert, string.format("http-connect.lua loaded"))
end
