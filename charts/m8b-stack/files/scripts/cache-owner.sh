#!/bin/sh
set -eu
uid=$(id -u searxng)
gid=$(id -g searxng)
# Idempotent after a partial init: CHOWN does not grant FOWNER to chmod again.
if [ "$(stat -c %a /cache)" != 750 ]; then
  chown 0:0 /cache
  chmod 0750 /cache
fi
chown "$uid:$gid" /cache
echo "Ephemeral cache prepared for numeric UID/GID $uid:$gid"
