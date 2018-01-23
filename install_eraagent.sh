#!/bin/bash

#############
# Variables #
#############            
webconsole_user="$1"
webconsole_pass="$2"
era_hostname="$3"

#############
# Functions #
#############

install_eraagent() {
  # Remove installer file if it exists
  if [ -f "agent-linux-x86_64.sh" ]; then
    /bin/rm -f -- "agent-linux-x86_64.sh" 
  fi
  
  # Download ERA Agent isntaller
  /usr/bin/wget https://download.eset.com/com/eset/apps/business/era/agent/latest/agent-linux-x86_64.sh
  
    # Check if download was succesful
  if [ "$?" != "0" ]; then
    exit 1
  fi
  
  # Install ERA Agent
  /bin/bash -- "agent-linux-x86_64.sh" --skip-license --hostname=$era_hostname --port=2222 --webconsole-user=$webconsole_user --webconsole-password=$webconsole_pass --webconsole-port=2223
  
    # Check if install was succesful
  if [ "$?" != "0" ]; then
    exit 3
  fi
  }
  
#######
# Run #
#######
install_eraagent

# Exit cleanly if all went well
exit 0
