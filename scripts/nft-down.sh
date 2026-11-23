#!/bin/sh
nft delete table inet sb 2>/dev/null
while ip rule del fwmark 1 table 100 2>/dev/null; do :; done
ip route flush table 100 2>/dev/null
while ip -6 rule del fwmark 1 table 106 2>/dev/null; do :; done
ip -6 route flush table 106 2>/dev/null
exit 0
