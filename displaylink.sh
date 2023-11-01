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
  [ $(id -u) -eq 0 ] || groups | grep -qw sudo || error 'Needs to be run by a user with sudo privileges or root'
  ps --no-headers -o comm 1 | grep -q systemd || error 'System is not using systemd'
  pkgs=$(apt-cache search evdi | cut -d ' ' -f 1 | grep -v -- -dev$)
  echo "$pkgs" | grep -q '^evdi-dkms$' || error 'Package evdi-dkms is not available'
  echo "$pkgs" | grep -q '^libevdi' || error 'Package libevdi* is not available'
}

sudo_install() {
  for dir in "$filesDir" "$(dirname "$0")/files"; do
    for file in $(find "$dir" -not -type d | sort); do
      if echo "$file" | grep -q sddm; then
        if ! dpkg -l | grep -q '^ii *sddm '; then
          echo "Skipping $file as sddm is not installed" >&2
          continue
        elif [ -f "$(echo "$file" | sed 's+.*files/+/+')" ]; then
          echo "Skipping $file (will not overwrite)" >&2
          continue
        fi
      fi

      fDir=$(dirname "$file" | sed 's+.*files/+/+')

      if echo "$fDir" | grep -q '^/etc/X11/xorg.conf.d'; then
        if [ ! -d "$fDir" ]; then
          echo "Skipping $file as X11 is not installed" >&2
          continue
        elif [ -f "$(echo "$file" | sed 's+.*files/+/+')" ]; then
          echo "Skipping $file (will not overwrite)" >&2
          continue
        fi
      fi

      [ -d "$fDir" ] || mkdir -vp "$fDir"
      cp -vd "$file" "$fDir"
    done
  done

  sed -i "s/###SOFTDEPS###/$(lsmod | grep ^drm_kms_helper | sed 's/.* //;s/evdi//;s/,,/,/;s/^,//;s/,$//' | tr , ' ')/" /etc/modprobe.d/evdi.conf
  dpkg -l | grep -q '^ii *evdi-dkms ' || apt-get install evdi-dkms
  dpkg -l | grep -q '^ii *libevdi' || apt-get install $(apt-cache depends evdi-dkms | grep -o 'libevdi[^ ]*' | head -1 | grep .)
  ln -sf $(dpkg -S libevdi.so | sort | head -1 | sed 's/.*: //' | grep .) /opt/displaylink/libevdi.so

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
  check_prerequisites
  tmpDir=$(mktemp -d)
  trap "rm -r '$tmpDir'" INT QUIT EXIT
  unzip -q "$1" -d "$tmpDir"
  driverDir="$tmpDir/displaylink-driver"
  mkdir "$driverDir" && (cd "$driverDir" && sh "$tmpDir"/displaylink-driver-*-*.run --tar xf && [ -f LICENSE ])
  filesDir="$tmpDir/files"
  mkdir -p "$filesDir/opt/displaylink" && (cd "$driverDir" && mv 3rd_party_licences.txt LICENSE *.spkg x64-*/* "$filesDir/opt/displaylink")

  if [ $(id -u) -ne 0 ]; then
    echo "Needing root privileges now to copy files"
    echo 'Press Return to continue'
    read line
  fi

  sudo "$0" sudo_install "$filesDir"
}

uninstall() {
  # TODO
  echo 'Unimplemented!!!!' >&2
  exit 1
}

if [ "$1" = '--uninstall' ]; then
  uninstall
elif [ -f "$1" ] && basename "$1" | grep -q '^DisplayLink USB Graphics Software for Ubuntu[0-9.]*-EXE.zip$'; then
  install "$1"
elif [ "$1" = 'sudo_install' -a -d "$2" ]; then
  filesDir=$2
  sudo_install
else
  usage
fi
