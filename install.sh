#! /bin/bash -e

argvZero="$0"

if [ `uname -s` = Darwin ]; then
  [ "${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX=/usr/local/ # SIP in El Capitan :(
else
  [ "${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX=/
fi

link()
{
  local src="$1"
  local target="$2"

  if [ -h "$target" ] || [ ! -f "$target" ]; then
    rm -f "$target"
  fi
  if [ -e "$target" ]; then
    echo "$target: file exists" >&2
    exit 1
  fi
  ln -vs "$src" "$target"
}

xcopy()
{
  local src="$1"
  local target="$2"
  mkdir -p "${target}"
    
  find "$src" -type f \
  | egrep -v '~$' \
  | $tar -cf - -T - \
  | (cd "$target" && $tar -xvf -)
}

locate()
{
  OLDIFS="$IFS"
  for filename in $*
  do
    IFS=":"
    for path in $PATH
    do
      if [ -f "${path}/${filename}" ]; then
        echo "${path}/${filename}"
        IFS="$OLDIFS"
        return 0
      fi
    done
  done

  IFS="$OLDIFS"
  return 1
}

assertLocate()
{
  while [ "$1" ]
  do
    if ! locate "$1" >/dev/null; then
      echo "$1: not found - please install package before installing shystemd" >&2
      exit 1
    fi
    shift
  done
}

set -o pipefail

echo "Installing shystem in ${SHYSTEMD_PREFIX}"
[ "`id -u`" != "0" ] && echo "Warning: you'll probably need root for this"

cd "`dirname $argvZero`/."
myDir="`pwd`"
mkdir -p "${SHYSTEMD_PREFIX}"
cd "${SHYSTEMD_PREFIX}"
SHYSTEMD_PREFIX="`pwd`"
cd "${myDir}"

locate gmake && make=gmake || make=make
locate gtar && make=gmake || tar=tar

assertLocate daemon
assertLocate $make
assertLocate $tar

xcopy bin "${SHYSTEMD_PREFIX}"
xcopy etc "${SHYSTEMD_PREFIX}"

if [ "${SHYSTEMD_PREFIX}" = "/" ]; then
  xcopy usr "${SHYSTEMD_PREFIX}"
else
  cd usr
  xcopy * "${SHYSTEMD_PREFIX}"
  cd ..
fi

link "${SHYSTEMD_PREFIX}"/bin/shystemctl "${SHYSTEMD_PREFIX}"/bin/systemctl
link "${SHYSTEMD_PREFIX}"/bin/jhournalctl "${SHYSTEMD_PREFIX}"/bin/journalctl


