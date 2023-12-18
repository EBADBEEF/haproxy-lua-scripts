local socket = require("socket")

-- argv can be used to pass in values from lua-load
local argv = table.pack(...)

-- byte to string convenience functions, haproxy expects these to be strings.
-- stolen from https://gist.github.com/trimsj/da37da55994a07bc1c602a22f13cbdb4
function string.bytes_to_uint16(str)
    return (str:byte(1)*256+str:byte(2))
end
function string.bytes_to_ip4(str)
    return (str:gsub('.', function (c) return string.format('%d.', string.byte(c)) end):sub(1,-2))
end
function string.bytes_to_ip6(str)
    return (str:gsub('..', function (c) return string.format('%02x%02x:', string.byte(c), string.byte(c,2)) end):sub(1,-2))
end
function string.bytes_to_hex(str)
    return (str:gsub('.', function (c) return string.format('%02x', string.byte(c)) end))
end

local function log(txn, lvl, ...)
    local args = { ... }
    table.insert(args, 1, "socks5:")
    txn:log(lvl, table.concat(args, " "))
end

local function dbg(txn, ...) log(txn, core.debug, ...) end
local function info(txn, ...) log(txn, core.info, ...) end
local function notice(txn, ...) log(txn, core.notice, ...) end

-- Read from request channel buffer and remove (consume). Wait for all the
-- bytes we requested or timeout due to tcp inspect-delay.
local function getbuf(txn, len)
  local data = txn.req:data(0, len)
  if data:len() == len then
    txn.req:remove(0, data:len())
    dbg(txn, string.format("<  getbuf  len=%2d, %s",data:len(),data:bytes_to_hex()))
    return data
  end
  dbg(txn, "no data")
  return nil
end

-- Send to response channel buffer, assume there is enough space
local function sendbuf(txn, data)
  dbg(txn, string.format(" > sendbuf len=%2d, %s",data:len(),data:bytes_to_hex()))
  txn.res:send(data)
end

local function is_socks5_with_authmethod(txn, method)
    local data = getbuf(txn, 2)
    if data == nil then
        return false
    end
    -- only support socks v5 for now
    if data:byte(1) ~= 0x05 then
        dbg(txn, "socks version not 5")
        return false
    end
    -- find our authmethod
    local nmethods = data:byte(2)
    local data = getbuf(txn, nmethods)
    if data == nil then
        return false
    end
    local found = false
    for idx = 1, nmethods do
        if data:byte(idx) == method then
            found = true
            break
        end
    end
    if not found then
        dbg(txn, string.format("did not find auth method 0x%02x", method))
        return false
    end
    return true
end

local function get_connect_address_type(txn)
    -- read ver, cmd, rsv, atyp
    local data = getbuf(txn, 4)
    if data:byte(1) ~= 0x05 then
        dbg(txn, "version mismatch")
        return nil
    end
    if data:byte(2) ~= 0x01 then
        dbg(txn, "unsupported method")
        return nil
    end
    return data:byte(4)
end

local function decode_address(txn, atyp)
    local addr_len = nil
    local family = ""

    if atyp == 0x01 then
        addr_len = 4
        family = 'inet'
    elseif atyp == 0x04 then
        addr_len = 16
        family = 'inet6'
    elseif atyp == 0x03 then
        addr_len = getbuf(txn, 1)
        if addr_len ~= nil then
            addr_len = addr_len:byte(1)
        end
    end

    if addr_len == nil then
        dbg(txn, "bad addr_len")
        return nil
    end

    local addr = getbuf(txn, addr_len)
    if addr == nil then
        dbg(txn, string.format("bad addr, addr_len=%d",addr_len))
        return nil
    end

    local port = getbuf(txn, 2)
    if port == nil then
        dbg(txn, "bad port")
        return nil
    end

    -- convert to string
    if atyp == 0x01 then
        addr = addr:bytes_to_ip4()
    elseif atyp == 0x04 then
        addr = addr:bytes_to_ip6()
    end
    port = port:bytes_to_uint16()

    notice(txn, string.format("%s:%s connect to %s:%s", 
        txn.sf:src(), txn.sf:src_port(), addr, port))

    -- resolve hostname
    if atyp == 0x03 then
        local ai = socket.dns.getaddrinfo(addr)
        if ai == nil then
            dbg(txn, string.format("could not resolve host: %s", addr))
            -- TODO: return SOCKS error msg
            return nil
        end
        dbg(txn, string.format("resolved host %s to %s", addr, ai[1].addr))
        addr = ai[1].addr
        family = ai[1].family
    end

    return addr, port, family
end

local function socks5_connect(txn)
    -- only support "no auth required" auth method
    if not is_socks5_with_authmethod(txn, 0x00) then
        return act.DENY
    end

    -- accept socks v5
    sendbuf(txn, '\x05\x00')

    -- tcp connect request (0x01) with address type
    atyp = get_connect_address_type(txn)
    if atyp == nil then
        return act.DENY
    end

    local family = ""
    local addr = ""
    local port = ""

    local addr, port, family = decode_address(txn, atyp)
    if family == nil then
        return act.DENY
    end

    -- send success back to client
    if family == "inet" then
      sendbuf(txn, '\x05\x00\x00\x01'
        .. '\x00\x00\x00\x00'
        .. '\x00\x00')
    elseif family == "inet6" then
        sendbuf(txn, '\x05\x00\x00\x04'
          .. '\x00\x00\x00\x00\x00\x00\x00\x00'
          .. '\x00\x00\x00\x00\x00\x00\x00\x00'
          .. '\x00\x00')
    end

    -- tell haproxy where to go
    dbg(txn, string.format("ready dst=%s, port=%s", addr, port))
    txn:set_var('txn.dst', addr)
    txn:set_var('txn.port', port)

    -- let the connection flow in haproxy now
    return act.CONTINUE
end

core.register_action("socks5", { 'tcp-req' }, socks5_connect, 0)
if core.thread == 1 then
core.log(core.alert, string.format("socks5.lua loaded"))
end
