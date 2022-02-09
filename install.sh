#! /bin/bash -e

if [ `uname -s` = Darwin ]; then
  [ "${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX=/usr/local/root # SIP in El Capitan :(
else
  [ "${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX=/
fi

link()
{
  local src="$1"
  local target="${SHYSTEMD_PREFIX}/$2"

  if [ -h "$target" ] || [ ! -f "$target" ]; then
    rm -f "$target"
  fi
  if [ -e "$target" ]; then
    echo "$target: file exists" >&2
    exit 1
  fi
  ln -s "$src" "$target"
}

xcopy()
{
  mkdir -p "${SHYSTEMD_PREFIX}"
    
  find "$1" -type f \
  | egrep -v '~$' \
  | tar -cf - -T - \
  | (cd "${SHYSTEMD_PREFIX}" && tar -xvf -)
}

set -o pipefail
cd "`dirname $0`/."

xcopy bin
xcopy etc
xcopy usr
link bin/shystemctl bin/systemctl
link bin/jhournalctl bin/journalctl

