#!/bin/sh
set -eu

app_dir=/opt/apps/com.volcengine.feilian/files
state_dir=/home/feilian/.feilian-service-state
mkdir -p "$state_dir"
chmod 755 "$state_dir"

# Feilian writes authentication and device state beside its binaries. Keep only
# those writable paths in the existing home volume, leaving binaries in the image.
for name in data cert; do
  source_path="$app_dir/$name"
  state_path="$state_dir/$name"
  if [ -L "$source_path" ] && [ "$(readlink "$source_path")" = "$state_path" ] && [ -d "$state_path" ]; then
    continue
  fi
  if [ -d "$source_path" ]; then
    if [ -d "$state_path" ]; then
      cp -an "$source_path/." "$state_path/"
      rm -rf "$source_path"
    else
      mv "$source_path" "$state_path"
    fi
  else
    mkdir -p "$state_path"
    [ ! -e "$source_path" ] || rm -f "$source_path"
  fi
  ln -s "$state_path" "$source_path"
done

for name in device.conf vpn.conf corplink.conf localserver.conf localserver.key localserver.pem .config.json rpc.conf; do
  source_path="$app_dir/$name"
  state_path="$state_dir/$name"
  if [ -L "$source_path" ] && [ "$(readlink "$source_path")" = "$state_path" ]; then
    continue
  fi
  if [ -e "$source_path" ]; then
    mv -f "$source_path" "$state_path"
  elif [ -L "$source_path" ]; then
    rm -f "$source_path"
  fi
  ln -s "$state_path" "$source_path"
done
