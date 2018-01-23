#!/bin/bash

#############
# Variables #
#############            
eav_user="$1"
eav_pass="$2"
lic_base64="$3"
wwwi_user="$4"
wwwi_pass="$5"
admin_email="$6"
domain="$7"
relay_to="$8"
fqdn="${10}"
adminusername="$9"
baseurl="https://raw.githubusercontent.com/esetnl/azure-relay/master"

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
    "nginx"
    "iptables-persistent"
    "unattended-upgrades"
    "software-properties-common"
    "bsd-mailx"
  )

  # List of debconf options
  debconf_options=(
    "iptables-persistent iptables-persistent/autosave_v4 boolean false"
    "iptables-persistent iptables-persistent/autosave_v6 boolean false"
  )

  # Set debconf options
  if [ -f "/tmp/debconf_options.txt" ]; then
    /bin/rm -f -- "/tmp/debconf_options.txt"
  fi

  for debconf_option in "${debconf_options[@]}"; do
    /bin/echo "$debconf_option" >> "/tmp/debconf_options.txt"
  done

  /usr/bin/debconf-set-selections -- "/tmp/debconf_options.txt"

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
  /opt/eset/esets/sbin/esets_set --set="listen_port=443" --section="wwwi"
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
    /usr/bin/wget -O "/etc/systemd/system/socat.service" -- "$baseurl/socat.service"
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
  # Create directory if it doesn't exist
  if [ ! -d '/etc/iptables' ]; then
    /bin/mkdir "/etc/iptables"
  fi

  # Back-up old rules
  if [ -f "/etc/iptables/rules.v4" ]; then
    /bin/cp "/etc/iptables/rules.v4" "/etc/iptables/rules.v4.bak"
  fi

  if [ -f "/etc/iptables/rules.v6" ]; then
    /bin/cp "/etc/iptables/rules.v6" "/etc/iptables/rules.v6.bak"
  fi

  # IPv4 config
  /usr/bin/wget -O "/etc/iptables/rules.v4" -- "$baseurl/rules.v4"
  
  # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 14
  fi

  /bin/chmod 600 -- "/etc/iptables/rules.v4"

  # IPv6 Config
  /usr/bin/wget -O "/etc/iptables/rules.v6" -- "$baseurl/rules.v6"
  
  # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 15
  fi

  /bin/chmod 600 -- "/etc/iptables/rules.v6"

  # Apply new rules
  /bin/systemctl restart netfilter-persistent
}

configure_certificates() {
  # Add certbot repository and install certbot
  /usr/bin/add-apt-repository -y -- "ppa:certbot/certbot"
  /usr/bin/apt-get "update"
  /usr/bin/apt-get -y install -- "certbot"

  # Request certificate
  /sbin/iptables -A INPUT -p tcp --dport 80 -j ACCEPT
  /usr/bin/certbot certonly --standalone --preferred-challenges http -d "$fqdn" -m "$admin_email" --agree-tos --no-eff-email

  # Check if request worked
  if [ "$?" != "0" ]; then
    exit 16
  fi
  /sbin/iptables -D INPUT -p tcp --dport 80 -j ACCEPT

  # Add to weekly cron
  if [ ! -f "/etc/cron.weekly/certbot" ]; then
    /usr/bin/wget -O "/etc/cron.weekly/certbot" -- "$baseurl/certbot"
    
    # Check if download was succesful
    if [ "$?" != "0" ]; then
      exit 17
    fi
  fi
}

configure_postfix() {
  /usr/bin/wget -O "/etc/postfix/main.cf" -- "$baseurl/main.cf"
  # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 18
  fi

  # Add alias for admin user
  /bin/echo "root: $admin_email" >> /etc/aliases
  /usr/bin/newaliases

  /bin/echo "root $admin_email" >> /etc/postfix/virtual
  /usr/sbin/postmap -- "/etc/postfix/virtual"

  # Change config
  /bin/sed -i "s|<azure-fqdn>|$fqdn|g" -- "/etc/postfix/main.cf"
  /bin/echo "$domain" > "/etc/postfix/domains"
  /bin/echo "$domain relay:[$relay_to]" > "/etc/postfix/transport"
  /usr/sbin/postmap -- "/etc/postfix/transport"
  /usr/sbin/postmap -- "/etc/postfix/virtual"

  # Restart postfix
  /bin/systemctl restart postfix
}
download_agentscript() {
 
    /usr/bin/wget -O "/home/$adminusername/install_eraagent.sh" -- "$baseurl/install_eraagent.sh"
    # Check if download was succesful
    if [ "$?" != "0" ]; then
      exit 19
    fi
}

configure_nginx() {
  /bin/sed -i 's|# server_tokens off;|server_tokens off;|g' /etc/nginx/nginx.conf
  /bin/rm /etc/nginx/sites-enabled/default
  /bin/mkdir /etc/nginx/ssl
  /bin/mkdir /etc/ssl/cert
  /usr/bin/openssl dhparam -out /etc/nginx/ssl/dhparams.pem 2048
  /bin/cat > /etc/nginx/sites-available/wwwi <<EOF
server {
  listen 80;
  return 301 https://\$host\$request_uri;
}

server {
  listen 443 ssl;
  add_header X-Frame-Options "SAMEORIGIN";
  add_header Strict-Transport-Security "max-age=31536000; includeSubDomains;";

  access_log /var/log/nginx/wwwi_access.log;
  error_log /var/log/nginx/wwwi_error.log;

  ssl_certificate /etc/ssl/cert/STAR_eracloud_nl.pem;
  ssl_certificate_key /etc/ssl/cert/star_eracloud_nl_key.pem;
  ssl_prefer_server_ciphers On;
  ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
  ssl_ciphers ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-DSS-AES128-GCM-SHA256:kEDH+AESGCM:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA:ECDHE-ECDSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-DSS-AES128-SHA256:DHE-RSA-AES256-SHA256:DHE-DSS-AES256-SHA:DHE-RSA-AES256-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:AES:CAMELLIA:DES-CBC3-SHA:!aNULL:!eNULL:!EXPORT:!DES:!RC4:!MD5:!PSK:!aECDH:!EDH-DSS-DES-CBC3-SHA:!EDH-RSA-DES-CBC3-SHA:!KRB5-DES-CBC3-SHA;
  ssl_dhparam /etc/nginx/ssl/dhparams.pem;

  location / {
  proxy_read_timeout 120;
  proxy_set_header X-Real-IP \$remote_addr;
  proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
  proxy_set_header Host \$http_host;
  proxy_pass http://127.0.0.1:8080;
  proxy_intercept_errors on;
  }

  error_page 400 401 402 403 404 405 406 407 408 409 410 411 412 413 414 415 416 417 418 420 422 423 424 426 428 429 431 444 449 450 451 500 501 502 503 504 505 506 507 508 509 510 511 /error.html;

  location /error.html {
    root /usr/share/nginx/html;
  }

  location ~ ^/$ {
  return 301 https://\$host;
  }
}
EOF
  ln -s /etc/nginx/sites-available/wwwi/etc/nginx/sites-enabled/wwi
  cp /usr/share/nginx/html/50x.html /usr/share/nginx/html/error.html
  service nginx reload
}
}

#######
# Run #
#######
install_packages
configure_iptables
install_esets
update_path
configure_esets
configure_socat
configure_certificates
configure_postfix
download_agentscript

# Exit cleanly if all went well
exit 0
