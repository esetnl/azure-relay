#!/bin/bash

#############
# Variables #
#############            
eav_user="$1"
eav_pass="$2"
lic_base64="$3"
wwwi_user="$4"
wwwi_pass="$5"

#############
# Functions #
#############

# Install needed packages
install_packages() {
  # Don't ask questions during installation of packages
  export DEBIAN_FRONTEND="noninteractive"
  export DEBCONF_NONINTERACTIVE_SEEN="true"

  # List of packages to be installed
  packages=(
    "libc6-i386"
    "socat"
    "postfix"
    "netfilter-persistent"
  )

  # List of debconf options
  debconf_options=(
    "netfilter-persistent netfilter-persistent/autosave_v4 boolean false"
    "netfilter-persistent netfilter-persistent/autosave_v6 boolean false"
  )

  if [ -f "/tmp/debconf_options.txt" ]; then
    /bin/rm -f -- "/tmp/debconf_options.txt"
  fi

  for debconf_option in "${debconf_options[@]}"; do
    /bin/echo "$debconf_option" >> "/tmp/debconf_options.txt"
  done

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

  # Cleanup
  /bin/rm -f -- "/tmp/debconf_options.txt"
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
  /opt/eset/esets/sbin/esets_set --set="av_update_password=$eav_pass" --section="global"

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
  /bin/rm -f -- "/tmp/MailSecurity.lic"
  /opt/eset/esets/sbin/esets_update

  # Configure smfi scanner
  /opt/eset/esets/sbin/esets_set --set="agent_enabled=yes" --section="smfi"
  /opt/eset/esets/sbin/esets_set --set="smfi_sock_path=/var/run/esets_smfi.sock" --section="smfi"

  # Enable wwwi
  /opt/eset/esets/sbin/esets_set --set="agent_enabled=yes" --section="wwwi"
  /opt/eset/esets/sbin/esets_set --set="listen_addr=0.0.0.0" --section="wwwi"
  /opt/eset/esets/sbin/esets_set --set="listen_port=8443" --section="wwwi"
  /opt/eset/esets/sbin/esets_set --set="username=$wwwi_user" --section="wwwi"
  /opt/eset/esets/sbin/esets_set --set="password=$wwwi_pass" --section="wwwi"

  # Configure antispam
  /opt/eset/esets/sbin/esets_set --set="action_as=scan" --section="smfi"
  /opt/eset/esets/sbin/esets_set --set="as_eml_header_modification=yes" --section="smfi"
  
  # Configure AV
  /opt/eset/esets/sbin/esets_set --set="av_quarantine_enabled=yes" --section="smfi"
  
  # Restart service
  /bin/systemctl restart esets
  # Check if restart was succesful
  if [ "$?" != "0" ]; then
    exit 10
  fi
}

# Configure socat to run as a service
configure_socat() {
  if [ ! -f "/etc/systemd/system/socat.service" ]; then
    /usr/bin/wget -O "/etc/systemd/system/socat.service" -- "https://raw.githubusercontent.com/d-maasland/azure-relay/master/socat.service"
    # Check if download was succesful
    if [ "$?" != "0" ]; then
      exit 11
    fi

    # Check if chmod was succesful
    if [ "$?" != "0" ]; then
      exit 12
    fi
    /bin/chmod 644 -- "/etc/systemd/system/socat.service"

    # Install the service
    /bin/systemctl enable socat
    # Check if install was succesful
    if [ "$?" != "0" ]; then
      exit 13
    fi
    /bin/systemctl start socat
  fi
}

configure_iptables() {
  # Back-up old rules
  if [ -f "/etc/iptables/rules.v4" ]; then
    /bin/cp "/etc/iptables/rules.v4" "/etc/iptables/rules.v4.bak"
  fi

  if [ -f "/etc/iptables/rules.v6" ]; then
    /bin/cp "/etc/iptables/rules.v6" "/etc/iptables/rules.v6.bak"
  fi

  # IPv4 config
  /usr/bin/wget -O "/etc/iptables/rules.v4" -- "https://raw.githubusercontent.com/d-maasland/azure-relay/master/rules.v4"
  
  # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 14
  fi

  /bin/chmod 600 -- "/etc/iptables/rules.v4"

  # IPv6 Config
  /usr/bin/wget -O "/etc/iptables/rules.v6" -- "https://raw.githubusercontent.com/d-maasland/azure-relay/master/rules.v6"
  
  # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 15
  fi

  /bin/chmod 600 -- "/etc/iptables/rules.v6"

  # Apply new rules
  /bin/systemctl restart netfilter-persistent
}

#######
# Run #
#######
install_packages
install_esets
update_path
configure_esets
configure_socat
configure_iptables

# Exit cleanly if all went well
exit 0