Example haproxy lua plugins.

See [haproxy.cfg](haproxy.cfg) for demo settings with explanations.

Run demo with `haproxy -f haproxy.cfg`, `nix develop`, or `nix-shell`.

Tested with:
- haproxy v2.8.4
- Lua 5.3

Some useful links to learn about haproxy lua plugins:
- https://www.arpalert.org/haproxy-lua.html
- https://docs.haproxy.org/2.8/configuration.html

# SOCKS v5 proxy (socks5.lua)

Use your haproxy server as a socks5 forward proxy. Clients connect to haproxy,
haproxy connects to the hosts (client <-> haproxy <-> host).

Supports:
- SOCKS v5
- Unauthorized method (i.e. no username or password supported)
- Username/Password authentication (but it accepts any username and password, just useful for logging)
- Connect type 0x01 (tcp connections) (i.e. no bind or udp)
- Address type ipv4, ipv6, or domain name

Inspired by @trimsj from here
https://gist.github.com/trimsj/da37da55994a07bc1c602a22f13cbdb4 but modified to
use haproxy's own dns resolver instead of lua-socket and refactored a bit. What
a cool idea. Thanks!

# HTTP CONNECT proxy (http-connect.lua)

Use your haproxy server as an http forward proxy. Only supports HTTP CONNECT.

# Inline Authentication (auth-inline.lua)

Add a password in front of services. Once user logs in, keeps session cookie
in-memory.

# Motivation

Why?? I like using haproxy. I wanted to block internet access from a subset of
services running in a user-namespaced container running on my system and found
that systemd's bpf firewall does not work (at the very least without
CAP_SYS_ADMIN). So I thought "let's use a socks proxy" and of course I just
couldn't use any existing package and well, here we are.

Also I wanted to understand how lua works in haproxy. It was hard to wrap my
head around.
