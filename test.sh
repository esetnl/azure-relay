#!/bin/bash

eav_user="$1"
eav_pass="$2"
esets_url="https://download.eset.com/com/eset/apps/business/es/linux/latest/esets.amd64.deb.bin"

wget --user="$eav_user" --password="$eav_pass" "$esest_url"