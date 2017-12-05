#!/bin/bash

eav_user="$1"
eav_pass="$1"
esets_url="https://download.eset.com/com/eset/apps/business/es/linux/latest/esets.amd64.deb.bin"

wget --user="$eav_user" --pass="$eav_pass" "$esest_url"