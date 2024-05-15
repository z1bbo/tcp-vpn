#!/bin/bash

echo "Running OpenVPN 'up' script to set DNS servers."

# Loop through each foreign_option_* variable
for optionname in ${!foreign_option_*} ; do
  option="${!optionname}"
  echo "Processing foreign_option: $option"
  
  # Check for DHCP options for DNS and add them
  if [[ $option =~ ^dhcp-option[[:space:]]DNS[[:space:]]([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+) ]]; then
    echo "Setting DNS server to: ${BASH_REMATCH[1]}"
    /usr/sbin/networksetup -setdnsservers "Wi-Fi" "${BASH_REMATCH[1]}"
  else
    echo "No matching DNS option found."
  fi
done

echo "OpenVPN 'up' script execution complete."
