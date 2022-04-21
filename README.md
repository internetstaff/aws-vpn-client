# aws-vpn-client

This is PoC to connect to the AWS Client VPN with OSS OpenVPN using SAML
authentication. Tested on macOS and Linux, should also work on other POSIX OS with a minor changes.

See [my blog post](https://smallhacks.wordpress.com/2020/07/08/aws-client-vpn-internals/) for the implementation details.

P.S. Recently [AWS released Linux desktop client](https://aws.amazon.com/about-aws/whats-new/2021/06/aws-client-vpn-launches-desktop-client-for-linux/), however, it is currently available only for Ubuntu, using Mono and is closed source. 
Consider opening a ticket asking for RPM distribution support! 

## Content of the repository

- [openvpn-v2.5.1-aws.patch](openvpn-v2.5.1-aws.patch) - patch required to build
AWS compatible OpenVPN v2.5.1, based on the
[AWS source code](https://amazon-source-code-downloads.s3.amazonaws.com/aws/clientvpn/osx-v1.2.5/openvpn-2.4.5-aws-2.tar.gz) (thanks to @heprotecbuthealsoattac) for the link.
- [server.go](server.go) - Go server to listed on http://127.0.0.1:35001 and save
SAML Post data to the file
- [aws-connect.sh](aws-connect.sh) - bash wrapper to run OpenVPN. It runs OpenVPN first time to get SAML Redirect and open browser and second time with actual SAML response

## How to use

1. Download openvpn 2.5.1 source.
2. patch -p1 < ../aws-vpn-client/openvpn-v2.5.1-aws.patch
3. Copy or symlink openvpn-2.5.1/src/openvpn/openvpn into aws-vpn-client directory.
4. Download your AWS Client VPN .ovpn config file.
6. Run `aws-connect.sh <OVPN FILE>`

## DNS
- Supports a `domains.txt` file with a list of domains to resolve via VPN.
- Will automatically use https://github.com/jonathanio/update-systemd-resolved for name resolution on systemd systems.

## Todo

Better integrate SAML HTTP server with a script or rewrite everything on golang
