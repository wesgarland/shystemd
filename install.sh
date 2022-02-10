#! /bin/bash -e
#
# @file         install.sh
#               Installer for shystemd. Uses LSB layout when SHYSTEMD_PREFIX=/ (default)
# @author       Wes Garland, wes@kingsds.network
# @date         Feb 2022
#

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
if [ "`id -u`" != "0" ]; then
  what=`basename "${SHYSTEMD_PREFIX}"`
  [ "$what" = "`find \"$where\"  -maxdepth 0 -uid 0 -type d -name / 2>/dev/null`" ] \
    && echo "Warning: you'll probably need root for this"
fi

if [ ! "${TRUST_ME}" ] && [ -f "${SHYSTEMD_PREFIX}/bin/systemctl" ] && [ ! -h "${SHYSTEMD_PREFIX}/bin/systemctl" ]; then
  echo "${SHYSTEMD_PREFIX}/bin/systemctl appears to be real systemd; aborting install. Set TRUST_ME to bypass." >&2
  sleep 1
  exit 1
fi

cd "`dirname $argvZero`/."
myDir="`pwd`"
mkdir -p "${SHYSTEMD_PREFIX}"
cd "${SHYSTEMD_PREFIX}"
SHYSTEMD_PREFIX="`pwd`"
cd "${myDir}"

locate gmake && make=gmake || make=make
locate gtar && tar=gtar || tar=tar

assertLocate daemon
assertLocate $make
assertLocate $tar
assertLocate printf

xcopy etc "${SHYSTEMD_PREFIX}"
xcopy bin "${SHYSTEMD_PREFIX}"

if [ "${SHYSTEMD_PREFIX}" = "/" ]; then
  # LSB-style install
  xcopy usr "${SHYSTEMD_PREFIX}"
  cat > "${SHYSTEMD_PREFIX}/local-env.incl" <<EOF
  export SHYSTEMD_LIB_DIR="${SHYSTEMD_PREFIX}/usr/lib/shystemd"
  export SHYSTEMD_LIBEXEC_DIR="${SHYSTEMD_PREFIX}/usr/libexec/shystemd"
EOF
else
  # BSD-style install
  cd usr
  xcopy * "${SHYSTEMD_PREFIX}"
  cd ..
  export SHYSTEMD_LIB_DIR="${SHYSTEMD_PREFIX}/lib/shystemd"
  export SHYSTEMD_LIBEXEC_DIR="${SHYSTEMD_PREFIX}/libexec/shystemd"
fi

link "${SHYSTEMD_PREFIX}"/bin/shystemctl "${SHYSTEMD_PREFIX}"/bin/systemctl
link "${SHYSTEMD_PREFIX}"/bin/jhournalctl "${SHYSTEMD_PREFIX}"/bin/journalctl


