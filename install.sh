#! /bin/bash -e
# -*-  Mode: sh; tab-width: 8; indent-tabs-mode: nil; sh-basic-offset: 2; -*-
#
# @file         install.sh
#               Installer for shystemd. Uses LSB layout when SHYSTEMD_PREFIX=/ (default)
# @author       Wes Garland, wes@kingsds.network
# @date         Feb 2022
#

argvZero="$0"

if [ `uname -s` = Darwin ]; then
  [ "${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX=/usr/local/ # SIP in El Capitan :(
  [ ! "${LAYOUT}" ] && LAYOUT=BSD
else
  [ "${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX=/
  [ ! "${LAYOUT}" ] && LAYOUT=LSB
fi
[ ! "${LAYOUT}" ] && [ "${SHYSTEMD_PREFIX}" = "/" ] && LAYOUT=LSB
[ ! "${LAYOUT}" ] && LAYOUT=BSD

cd "`dirname $argvZero`/."
myDir="`pwd`"
mkdir -p "${SHYSTEMD_PREFIX}"
cd "${SHYSTEMD_PREFIX}" || exit 1
SHYSTEMD_PREFIX="`pwd`"

cd "${myDir}"
. usr/lib/shystemd/locate
. etc/shystemd/default-env.incl

# Make a symbolic link, safely, without overwriting something
# other than a symlink. This is to avoid accidentally clobbering
# a real systemd installation.
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

# Copy a directory tree
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

# Main Program Entry Point
set -o pipefail
echo "Installing shystemd in ${SHYSTEMD_PREFIX}"

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

# Ensure we have the necessary prequisites
locate gmake && make=gmake || make=make
locate gtar  && tar=gtar   || tar=tar

assertLocate daemon
assertLocate $make
assertLocate $tar
assertLocate printf

$make -C range-find
mv range-find/range-find bin

# Begin the actual install
xcopy etc "${SHYSTEMD_PREFIX}"
xcopy bin "${SHYSTEMD_PREFIX}"

# Build a local config describing this install
[ ! "${JHOURNALD_LOG_DIR}" ] && JHOURNALD_LOG_DIR="${SHYSTEMD_PREFIX}/var/log/shystemd/journals"
cat > "${SHYSTEMD_PREFIX}/etc/shystemd/local-env.incl" <<EOF1
[ "\${SHYSTEMD_PREFIX}" ] || SHYSTEMD_PREFIX="${SHYSTEMD_PREFIX}"
export JHOURNALD_LOG_DIR="${JHOURNALD_LOG_DIR}"
EOF1
echo mkdir -m1777 -p "${SHYSTEMD_PREFIX}/var/log/shystemd/journals"
mkdir -m1777 -p "${SHYSTEMD_PREFIX}/var/log/shystemd/journals"

if [ "${LAYOUT}" = "LSB" ]; then
  xcopy usr "${SHYSTEMD_PREFIX}"
  cat >> "${SHYSTEMD_PREFIX}/etc/shystemd/local-env.incl" <<EOF2
  export SHYSTEMD_LIB_DIR="${SHYSTEMD_PREFIX}/usr/lib/shystemd"
  export SHYSTEMD_LIBEXEC_DIR="${SHYSTEMD_PREFIX}/usr/libexec/shystemd"
EOF2
else # BSD layout
  cd usr
  xcopy * "${SHYSTEMD_PREFIX}"
  cd ..
  cat > "${SHYSTEMD_PREFIX}/etc/shystem/local-env.incl" <<EOF3
  export SHYSTEMD_LIB_DIR="${SHYSTEMD_PREFIX}/lib/shystemd"
  export SHYSTEMD_LIBEXEC_DIR="${SHYSTEMD_PREFIX}/libexec/shystemd"
EOF3
fi

link "${SHYSTEMD_PREFIX}"/bin/shystemctl "${SHYSTEMD_PREFIX}"/bin/systemctl
link "${SHYSTEMD_PREFIX}"/bin/jhournalctl "${SHYSTEMD_PREFIX}"/bin/journalctl

