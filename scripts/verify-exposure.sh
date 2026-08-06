#!/usr/bin/env bash
# Verify public exposure. Run this from a machine OUTSIDE your network
# (VPS, phone hotspot, friend's machine). Requires nmap.
# Expected result: 80 and 443 open. All other ports closed or filtered.
set -euo pipefail

TARGET="${1:?usage: verify-exposure.sh <public-ip-or-domain>}"

echo "== Top 1000 TCP ports =="
nmap -Pn "$TARGET"

echo
echo "== Full TCP sweep (slow) =="
read -rp "Run full 65535-port scan? [y/N] " ans
[[ "$ans" == [yY] ]] && nmap -Pn -p- --min-rate 2000 "$TARGET"

echo
echo "== Common UDP ports =="
read -rp "Run UDP scan (needs root)? [y/N] " ans
[[ "$ans" == [yY] ]] && sudo nmap -Pn -sU --top-ports 50 "$TARGET"

echo
echo "PASS criteria: only 80/tcp and 443/tcp (and 443/udp for HTTP/3) open."
echo "Anything else open = misconfiguration. Fix it before you continue."
