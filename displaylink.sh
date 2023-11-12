#!/bin/sh -e
IFS='
'

usage() {
  echo "Usage: $(basename "$0") (<DisplayLinkSoftware>|--uninstall)" >&2
  echo 'DisplayLinkSoftware can be downloaded from https://www.synaptics.com/products/displaylink-graphics/downloads/ubuntu' >&2
  exit 1
}

error() {
  echo "$*" >&2
  exit 1
}

check_prerequisites() {
  echo 'Checking prerequisites'
  ps --no-headers -o comm 1 | grep -q systemd || error 'System is not using systemd'
  pkgs=$(apt-cache search evdi | cut -d ' ' -f 1 | grep -v -- -dev$)
  echo "$pkgs" | grep -q '^evdi-dkms$' || error 'Package evdi-dkms is not available'
  echo "$pkgs" | grep -q '^libevdi' || error 'Package libevdi* is not available'
  [ $(id -u) -eq 0 ] || groups | grep -qw sudo || error 'Needs to be run by a user with sudo privileges or root'
}

check_service() {
  if systemctl -q is-active displaylink-driver.service; then
    echo
    echo "DisplayLink service is running, will stop it now"
    echo 'Press Return to continue'
    read line
    systemctl stop displaylink-driver.service
  fi
}

check_root() {
  if [ $(id -u) -ne 0 ]; then
    echo
    echo "Needing root privileges now to copy files"
    echo 'Press Return to continue'
    read line
  fi
}

sudo_install() {
  echo 'Copying files'

  for dir in "$filesDir" "$(dirname "$0")/files"; do
    for file in $(find "$dir" -not -type d | sort); do
      targetFile=$(echo "$file" | sed 's+.*files/+/+')
      targetDir=$(dirname "$targetFile")

      if echo "$file" | grep -q 'sddm'; then
        if ! dpkg -l | grep -q '^ii *sddm '; then
          echo "  Skipping $targetFile as sddm is not installed" >&2
          continue
        elif [ -f "$targetFile" ]; then
          echo "  Skipping $targetFile (will not overwrite)" >&2
          continue
        fi
      fi

      if echo "$file" | grep -q 'xorg.conf.d'; then
        if [ ! -d "$targetDir" ]; then
          echo "  Skipping $targetFile as X11 is not installed" >&2
          continue
        elif [ -f "$targetFile" ]; then
          echo "  Skipping $targetFile (will not overwrite)" >&2
          continue
        fi
      fi

      [ -d "$targetDir" ] || { echo "  Creating $targetDir"; mkdir -p "$targetDir"; }
      echo "  Copying $targetFile"
      cp -d "$file" "$targetDir"
    done
  done

  sed -i "s/###SOFTDEPS###/$(lsmod | grep ^drm_kms_helper | sed 's/.* //;s/evdi//;s/,,/,/;s/^,//;s/,$//' | tr , ' ')/" /etc/modprobe.d/evdi.conf
  echo 'Installing EVDI kernel module and library'
  dpkg -l | grep -q '^ii *evdi-dkms ' || apt-get install evdi-dkms
  dpkg -l | grep -q '^ii *libevdi' || apt-get install $(apt-cache depends evdi-dkms | grep -o 'libevdi[^ ]*' | head -1 | grep .)
  ln -sf $(dpkg -S libevdi.so | sort | head -1 | sed 's/.*: //' | grep .) /opt/displaylink/libevdi.so
  echo 'Checking EFI status'

  if [ -d /sys/firmware/efi ]; then
    dpkg -l | grep -q '^ii *mokutil ' || apt-get install mokutil

    if mokutil --sb-state | grep -q enabled; then
      if ! mokutil --list-enrolled | grep '^SHA1 Fingerprint' | grep -qi "$(openssl x509 -fingerprint -in /var/lib/dkms/mok.pub -noout | sed 's/.*=//')"; then
        reload=no
        echo
        echo 'You need to import the dkms mok key as SecureBoot is enabled; otherwise the kernel module cannot be loaded.'
        echo
        echo 'Make up a password and set it in the following dialog'
        echo 'Then reboot and import the key with the chosen password'
        echo 'After that, DisplayLink should be working'
        echo 'Press Return to continue'
        read line
        mokutil --import /var/lib/dkms/mok.pub
      fi
    fi
  fi

  if [ "$reload" != 'no' ]; then
    echo
    echo 'Installation has been successful. A reboot is necessary as the kernel module (evdi) must be loaded before X11 is started'
    exit
    # X11 freezes when evdi module is loaded. Otherwise, the code below would work
    echo 'Reloading systemd and udev'
    systemctl daemon-reload
    udevadm control -R
    echo
    echo 'Installation has been successful. If any DisplayLink devices are connected, they will now be activated'
    echo 'Press Return to continue'
    read line

    grep -lw 17e9 /sys/bus/usb/devices/*/idVendor | while read device; do
      udevadm trigger --action=add "$(dirname "$device")"
    done
  fi
}

install() {
  echo "Installing from $1"
  check_prerequisites
  check_service
  echo 'Unpacking DisplayLinkSoftware'
  tmpDir=$(mktemp -d)
  trap "rm -rf '$tmpDir'" INT QUIT EXIT
  unzip -q "$1" -d "$tmpDir"
  driverDir="$tmpDir/displaylink-driver"
  mkdir "$driverDir" && (cd "$driverDir" && sh "$tmpDir"/displaylink-driver-*-*.run --tar xf && [ -f LICENSE ])
  echo 'Preparing files to copy'
  filesDir="$tmpDir/files"
  mkdir -p "$filesDir/opt/displaylink" && (cd "$driverDir" && mv 3rd_party_licences.txt LICENSE *.spkg x64-*/* "$filesDir/opt/displaylink")
  check_root
  sudo "$0" sudo_install "$filesDir"
}

rmdir_recursive() {
  if [ $(ls -a "$1" | wc -l) -eq 2 ] && ! dpkg -S "$1" >/dev/null 2>&1; then
    echo "  Removing directory $1"
    rmdir "$1"
    rmdir_recursive "$(dirname "$1")"
  fi
}

sudo_uninstall() {
  echo 'Removing files'

  for file in $(find "$(dirname "$0")/files" -not -type d | grep -v /files/opt/displaylink/ | sort); do
    targetFile=$(echo "$file" | sed 's+.*files/+/+')
    targetDir=$(dirname "$targetFile")
    [ -e "$targetFile" ] || continue

    if echo "$file" | grep -qE 'sddm|xorg.conf.d'; then
      if [ "$(cat "$targetFile" | md5sum)" != "$(cat "$file" | md5sum)" ]; then
        echo "  Skipping $targetFile as it differs from included file" >&2
        continue
      fi
    fi

    echo "  Removing $targetFile"
    rm "$targetFile"
    rmdir_recursive "$targetDir"
  done

  if [ -d /opt/displaylink ]; then
    echo '  Removing /opt/displaylink'
    rm -r /opt/displaylink
  fi

  echo 'Reloading systemd and udev'
  systemctl daemon-reload
  udevadm control -R
  echo 'Uninstalling EVDI kernel module and library'
  dpkg -l | grep -q '^ii *evdi-dkms ' && apt-get purge evdi-dkms $(dpkg -l | grep '^ii *libevdi' | sed 's/^ii *//;s/ .*//')
  echo
  echo 'Uninstall has been successful. The kernel module (evdi) will be unloaded with next reboot/shutdown'
}

uninstall() {
  echo 'Uninstalling'
  check_service
  check_root
  sudo "$0" sudo_uninstall
}

if [ "$1" = '--uninstall' ]; then
  uninstall
elif [ -f "$1" ] && basename "$1" | grep -q '^DisplayLink USB Graphics Software for Ubuntu[0-9.]*-EXE.zip$'; then
  install "$1"
elif [ "$1" = 'sudo_install' -a -d "$2" ]; then
  filesDir=$2
  sudo_install
elif [ "$1" = 'sudo_uninstall' ]; then
  sudo_uninstall
else
  usage
fi
