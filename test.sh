#!/bin/bash

#############
# Variables #
#############            
eav_user="$1"
eav_pass="$2"
lic_base64="$3"

#############
# Functions #
#############

# Install needed packages
install_packages() {
  # Don't ask questions during installation of packages
  export DEBIAN_FRONTEND="noninteractive"

  # List of packages to be installed
  packages=(
    "libc6-i386"
    "socat"
    "postfix"
  )

  # Update package list
  /usr/bin/apt-get "update"

  # Check if update was succesful
  if [ "$?" != "0" ]; then
    exit 3
  fi

  # Install packages
  for package in "${packages[@]}"; do
    /usr/bin/apt-get -y install -- "$package"

    # Check if install was succesful
    if [ "$?" != "0" ]; then
      exit 4
    fi
  done
}

# Download and install esets
install_esets() {
  # Remove installer file if it exists
  if [ -f "esets.amd64.deb.bin" ]; then
    /bin/rm -f -- "esets.amd64.deb.bin" 
  fi

  # Download esets installer
  /usr/bin/wget --user="$eav_user" --password="$eav_pass" -- "https://download.eset.com/com/eset/apps/business/es/linux/latest/esets.amd64.deb.bin"
  
  # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 1
  fi

  # Install esets
  /bin/bash -- "esets.amd64.deb.bin" --skip-license

  # Check if install was succesful
  if [ "$?" != "0" ]; then
    exit 2
  else
    /bin/rm -f -- "esets.amd64.deb.bin"
  fi
}

# Add eset directories to path
update_path() {
  if ! /bin/grep -q '/opt/eset/esets' -- "/etc/environment"; then
    source -- "/etc/environment"
    /bin/sed -i "s|^PATH=.\+$|PATH=\"$PATH:/opt/eset/esets/bin:/opt/eset/esets/sbin\"|" -- "/etc/environment"

    # Check if update was succesful
    if [ "$?" != "0" ]; then
      exit 5
    fi
  fi
}

# Congigure esets options
configure_esets() {
  # Set update username and password
  /opt/eset/esets/sbin/esets_set --set="av_update_username=$eav_user" --section="global"
  # Check if set was succesful
  if [ "$?" != "0" ]; then
    exit 6
  fi

  /opt/eset/esets/sbin/esets_set --set="av_update_password=$eav_pass" --section="global"
  # Check if set was succesful
  if [ "$?" != "0" ]; then
    exit 6
  fi

  # Import lic file
  if [ -f "/tmp/MailSecurity.lic" ]; then
    /bin/rm -f -- "/tmp/MailSecurity.lic"
  fi

  # Decode license file
  /bin/echo "$lic_base64" | /usr/bin/base64 -d > "/tmp/MailSecurity.lic"
  # Check if decode was succesful
  if [ "$?" != "0" ]; then
    exit 7
  fi

  # Import license file
  /opt/eset/esets/sbin/esets_lic --import "/tmp/MailSecurity.lic"
  # Check if import was succesful
  if [ "$?" != "0" ]; then
    exit 8
  else
    /bin/rm -f -- "/tmp/MailSecurity.lic"
    
    # Update esets
    /opt/eset/esets/sbin/esets_update
  fi

  # Configure smfi scanner
  /opt/eset/esets/sbin/esets_set --set="agent_enabled=yes" --section="smfi"
  # Check if set was succesful
  if [ "$?" != "0" ]; then
    exit 9
  fi

  /opt/eset/esets/sbin/esets_set --set="smfi_sock_path=/var/run/esets_smfi.sock" --section="smfi"
  # Check if set was succesful
  if [ "$?" != "0" ]; then
    exit 9
  fi

  # Restart service
  /usr/sbin/service esets restart
  # Check if restart was succesful
  if [ "$?" != "0" ]; then
    exit 10
  fi
}

#######
# Run #
#######
install_packages
install_esets
update_path
configure_esets

# Exit cleanly if all went well
exit 0