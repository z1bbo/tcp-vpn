#!/bin/bash

echo "Running OpenVPN 'down' script to reset DNS servers."

# Reset DNS settings to DHCP-assigned servers
echo "Resetting DNS settings to DHCP defaults."
/usr/sbin/networksetup -setdnsservers "Wi-Fi" empty

echo "OpenVPN 'down' script execution complete."
