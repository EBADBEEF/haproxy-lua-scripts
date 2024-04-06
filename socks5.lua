-- argv can be used to pass in values from lua-load
local argv = table.pack(...)

-- some convenience logging functions
local function log(txn, lvl, ...)
    txn:log(lvl, "socks5: " .. string.format(...))
    --print("socks5: " .. string.format(...))
end
local function dbg(txn, ...) log(txn, core.debug, ...) end
local function info(txn, ...) log(txn, core.info, ...) end
local function notice(txn, ...) log(txn, core.notice, ...) end

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

-- Read from request channel buffer and remove (consume). Wait for all the
-- bytes we requested or timeout due to tcp inspect-delay.
local function getbuf(txn, len)
  local data = txn.req:data(0, len)
  if data:len() == len then
    txn.req:remove(0, data:len())
    dbg(txn, "<  getbuf  len=%2d, %s",data:len(),data:bytes_to_hex())
    return data
  end
  dbg(txn, "no data")
  return nil
end

-- Send to response channel buffer, assume there is enough space
local function sendbuf(txn, data)
  dbg(txn, " > sendbuf len=%2d, %s", data:len(), data:bytes_to_hex())
  txn.res:send(data)
end

local function parse_userpass(txn)
    local version = getbuf(txn, 1)
    if version == nil or version:byte(1) ~= 0x01 then
        return nil, "username version mismatch"
    end
    local username_len = getbuf(txn, 1)
    if username_len == nil then
        return nil, "failed to read username length"
    end
    local username = getbuf(txn, username_len:byte(1))
    if username == nil then
        return nil, "failed to read username"
    end
    local password_len = getbuf(txn, 1)
    if password_len == nil then
        return nil, "failed to read password length"
    end
    local password = getbuf(txn, password_len:byte(1))
    return username, password
end

local function is_socks5(txn)
    local data = getbuf(txn, 2)
    if data == nil then
        return false, "no initial bytes"
    end
    -- only support socks v5 for now
    if data:byte(1) ~= 0x05 then
        return false, "socks version not 5"
    end
    -- find supported authmethod
    local nmethods = data:byte(2)
    local data = getbuf(txn, nmethods)
    if data == nil then
        return false, "failed to read nmethods"
    end
    -- prefer username/password
    for idx = 1, nmethods do
        if data:byte(idx) == 0x02 then
            sendbuf(txn, '\x05\x02')
            local username, password = parse_userpass(txn)
            if username == nil then
                return false, password
            end
            -- accept any password
            sendbuf(txn, '\x01\x00')
            return true, username
        end
    end
    -- ...but also support null auth
    for idx = 1, nmethods do
        if data:byte(idx) == 0x00 then
            sendbuf(txn, '\x05\x00')
            return true, nil
        end
    end
    return false, "could not find supported auth method"
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

-- return address and port as printable strings
local function decode_address(txn, atyp)
    local addr_len = nil

    if atyp == 0x01 then
        addr_len = 4
    elseif atyp == 0x04 then
        addr_len = 16
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
        dbg(txn, "bad addr, addr_len=%d",addr_len)
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
    elseif atyp == 0x03 then
        txn:set_var("req.resolvedns", true)
    end
    port = port:bytes_to_uint16()

    return addr, port
end

local function socks5_connect(txn)
    local ok, username = is_socks5(txn)
    if not ok then
        dbg(txn, username)
        return act.DENY
    end

    -- tcp connect request (0x01) with address type
    atyp = get_connect_address_type(txn)
    if atyp == nil then
        return act.DENY
    end

    local addr = ""
    local port = ""

    local addr, port = decode_address(txn, atyp)
    if addr == nil or port == nil then
        return act.DENY
    end

    notice(txn, "%s:%s%s connect to %s:%s",
        txn.sf:src(),
        txn.sf:src_port(),
        username and (' "' .. username .. '"') or "",
        addr,
        port
    )

    -- send success back to client
    sendbuf(txn, '\x05\x00\x00\x01'
      .. '\x00\x00\x00\x00'
      .. '\x00\x00')

    -- tell haproxy where to go
    txn:set_var('req.dst', addr)
    txn:set_var('req.port', port)

    -- let the connection flow in haproxy now
    return act.CONTINUE
end

core.register_action("socks5", { 'tcp-req' }, socks5_connect, 0)
if core.thread == 1 then
core.log(core.alert, string.format("socks5.lua loaded"))
end
