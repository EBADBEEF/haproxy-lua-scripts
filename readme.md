Use your haproxy server as a socks5 proxy. Clients connect to haproxy, haproxy
connects to the hosts (client <-> haproxy <-> host).

This is a socks5 proxy implemented in lua for haproxy. Tested with
- haproxy v2.8.4
- Lua 5.3
- LuaSocket 3.1.0

Supports:
- SOCKS v5
- Unauthorized method (i.e. no username or password supported)
- Connect type 0x01 (tcp connections) (i.e. no bind or udp)
- Address type ipv4, ipv6, or domain name

Stolen from @trimsj here
https://gist.github.com/trimsj/da37da55994a07bc1c602a22f13cbdb4 but improved.
What a cool idea. Thanks!

Some ideas for future development:
- add user auth
- custom filtering rules per-user and/or per-domain
- ldap lookup

Example haproxy debug output (annotated) from lua script using curl as the
client:
```
$ curl --socks5-hostname 127.0.0.1:1080 http://ipv6.google.com
socks5: <  getbuf  len= 2, 0502     (client wants socks v5...)
socks5: <  getbuf  len= 2, 0001     (...connect mode 0x01)
socks5:  > sendbuf len= 2, 0500     (server says ok)
socks5: <  getbuf  len= 4, 05010003 (client wants to connect to domain name)
socks5: <  getbuf  len= 1, 0f       (address length is 15)
socks5: <  getbuf  len=15, 697076362e676f6f676c652e636f6d (domain name)
socks5: <  getbuf  len= 2, 0050     (port number 80)
socks5: resolved host ipv6.google.com to 2607:f8b0:4005:812::200e
socks5:  > sendbuf len=22, 05000004000000000000000000000000000000000000
  (server says no error, bind address is 0 because we dont know source ip and port)

$ curl --socks5-hostname 127.0.0.1:1080 http://ipv4.google.com
socks5: <  getbuf  len= 2, 0502
socks5: <  getbuf  len= 2, 0001
socks5:  > sendbuf len= 2, 0500
socks5: <  getbuf  len= 4, 05010003
socks5: <  getbuf  len= 1, 0f
socks5: <  getbuf  len=15, 697076342e676f6f676c652e636f6d
socks5: <  getbuf  len= 2, 0050
socks5: resolved host ipv4.google.com to      142.251.46.238
socks5:  > sendbuf len=10, bytes=  05000001000000000000

$ curl --socks5-hostname 127.0.0.1:1080 http://127.0.0.1:8081
socks5: <  getbuf  len= 2, 0502
socks5: <  getbuf  len= 2, 0001
socks5:  > sendbuf len= 2, 0500
socks5: <  getbuf  len= 4, 05010001
socks5: <  getbuf  len= 4, 7f000001
socks5: <  getbuf  len= 2, 1f91
socks5:  > sendbuf len=10, 05000001000000000000
```

Why?? I like using haproxy. I wanted to block internet access from a subset of
services running in a user-namespaced container running on my system and found
that systemd's bpf firewall does not work (at the very least without
CAP_SYS_ADMIN). So I thought "let's use a socks proxy" and of course I just
couldn't use any existing package and well, here we are.

Also I wanted to understand how lua works in haproxy. It was hard to wrap my
head around.

Some useful links:
- https://www.arpalert.org/haproxy-lua.html
- https://docs.haproxy.org/2.8/configuration.html
