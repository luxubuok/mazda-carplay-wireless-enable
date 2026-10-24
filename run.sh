#!/bin/sh
# Wireless CarPlay Enabler/Disabler for Mazda CMU
# Target CMU Firmware: V74.x (e.g. 74.00.324)

hwclock --hctosys

echo 1 > /sys/class/gpio/Watchdog\ Disable/value
mount -o rw,remount /

MYDIR=$(dirname "$(readlink -f "$0")")
mount -o rw,remount ${MYDIR}

# --- Require CMU firmware V74 ---
get_cmu_ver()
{
  _ver=$(grep '^JCI_SW_VER=' /jci/version.ini | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -n1)
  echo ${_ver}
}

CMU_VER=$(get_cmu_ver)
CMU_MAJOR=$(echo "${CMU_VER}" | cut -d'.' -f1)

if [ "${CMU_MAJOR}" != "74" ]
then
  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="This installer requires CMU firmware V74.x.\nDetected version: V${CMU_VER}\nInstallation aborted.\nRemove USB drive.\nRebooting in 5 seconds..." \
    --no-cancel &
  sleep 5
  killall -q jci-dialog
  exit 1
fi

mkdir -p "${MYDIR}/logs"

TARGET_SCRIPT="/jci/scripts/get_board_type.sh"

# --- Prompt user: Enable, Disable, or Cancel ---
/jci/tools/jci-dialog --3-button-dialog \
  --title="Wireless CarPlay" \
  --text="Enable or Disable Wireless CarPlay?\nDetected CMU FW: V${CMU_VER}" \
  --ok-label="Enable" \
  --cancel-label="Disable" \
  --button3-label="Cancel"
CHOICE=$?

if [ $CHOICE -eq 0 ]
then
  # ============================================================
  # ENABLE WIRELESS CARPLAY
  # ============================================================
  exec > "${MYDIR}/logs/wcp_enable.log" 2>&1
  echo "=== Wireless CarPlay Enable start ==="
  echo "CMU Firmware: V${CMU_VER}"
  echo "Timestamp: $(date)"

  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Enabling Wireless CarPlay...\nDo not remove USB drive." --no-cancel &

  if [ -f "${TARGET_SCRIPT}" ]
  then
    # 1. Backup original get_board_type.sh if backup does not exist
    if [ ! -f "${TARGET_SCRIPT}.orig" ]
    then
      cp -a "${TARGET_SCRIPT}" "${TARGET_SCRIPT}.orig"
      echo "Created backup: ${TARGET_SCRIPT}.orig"
    else
      echo "Backup ${TARGET_SCRIPT}.orig already exists"
    fi

    # 2. Patch exit $ret -> exit 2
    if grep -q '^exit 2' "${TARGET_SCRIPT}"
    then
      echo "Already patched with exit 2"
    else
      sed -i 's/exit \$ret/exit 2/g' "${TARGET_SCRIPT}"
      echo "Patched ${TARGET_SCRIPT}: replaced 'exit \$ret' with 'exit 2'"
    fi

    chmod 0755 "${TARGET_SCRIPT}"
  else
    echo "ERROR: ${TARGET_SCRIPT} not found!"
  fi

  sync
  echo "=== Wireless CarPlay Enable complete ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Wireless CarPlay Enabled successfully!\nYou can remove the USB drive.\nRebooting in 5 seconds..." --no-cancel &

elif [ $CHOICE -eq 1 ]
then
  # ============================================================
  # DISABLE WIRELESS CARPLAY
  # ============================================================
  exec > "${MYDIR}/logs/wcp_disable.log" 2>&1
  echo "=== Wireless CarPlay Disable start ==="
  echo "CMU Firmware: V${CMU_VER}"
  echo "Timestamp: $(date)"

  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Disabling Wireless CarPlay...\nDo not remove USB drive." --no-cancel &

  if [ -f "${TARGET_SCRIPT}" ]
  then
    # Restore from .orig if available
    if [ -f "${TARGET_SCRIPT}.orig" ]
    then
      cp -a "${TARGET_SCRIPT}.orig" "${TARGET_SCRIPT}"
      rm -f "${TARGET_SCRIPT}.orig"
      echo "Restored ${TARGET_SCRIPT} from backup"
    else
      # Revert edit manually
      sed -i 's/exit 2/exit \$ret/g' "${TARGET_SCRIPT}"
      echo "Reverted ${TARGET_SCRIPT}: replaced 'exit 2' with 'exit \$ret'"
    fi

    chmod 0755 "${TARGET_SCRIPT}"
  else
    echo "ERROR: ${TARGET_SCRIPT} not found!"
  fi

  sync
  echo "=== Wireless CarPlay Disable complete ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Wireless CarPlay Disabled!\nRestored original settings.\nYou can remove the USB drive.\nRebooting in 5 seconds..." --no-cancel &

else
  # ============================================================
  # CANCEL
  # ============================================================
  sync
  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Cancelled.\nNothing was changed.\nYou can remove the USB drive." \
    --ok-label="Close" --no-cancel
  exit 0
fi

sleep 5
killall -q jci-dialog
reboot
exit 0