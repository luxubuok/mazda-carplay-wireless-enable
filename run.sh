#!/bin/sh
# Wireless CarPlay Enabler/Disabler for Mazda CMU
# Target CMU Firmware: V74.x (e.g. 74.00.324)
# Features: Wireless CarPlay activation + Clean Fix for DTC B119F:92-08

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
  --text="Enable or Disable Wireless CarPlay?\nDetected CMU FW: V${CMU_VER}\nIncludes DTC B119F Clean Fix" \
  --ok-label="Enable" \
  --cancel-label="Disable" \
  --button3-label="Cancel"
CHOICE=$?

if [ $CHOICE -eq 0 ]
then
  # ============================================================
  # ENABLE WIRELESS CARPLAY + DTC B119F FIX
  # ============================================================
  exec > "${MYDIR}/logs/wcp_enable.log" 2>&1
  echo "=== Wireless CarPlay Enable start ==="
  echo "CMU Firmware: V${CMU_VER}"
  echo "Timestamp: $(date)"

  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Enabling Wireless CarPlay...\nApplying DTC B119F fix...\nDo not remove USB drive." --no-cancel &

  # 1. Patch get_board_type.sh with smart multi-stage & process-tree detection
  if [ -f "${TARGET_SCRIPT}" ]
  then
    if [ ! -f "${TARGET_SCRIPT}.orig" ]
    then
      cp -a "${TARGET_SCRIPT}" "${TARGET_SCRIPT}.orig"
      echo "Created backup: ${TARGET_SCRIPT}.orig"
    else
      echo "Backup ${TARGET_SCRIPT}.orig already exists"
    fi

    cat << 'EOF' > "${TARGET_SCRIPT}"
#!/bin/sh
# Smart Board Type Detection for Wireless CarPlay with zero DTC B119F:92-08

# Ensure ublox.txt is cleaned up so OBD diagnostics stays in standard GPS mode
rm -f /data_persist/ublox.txt 2>/dev/null

# 1. Walk up process tree to detect caller
IS_VIM=0
IS_AUTOSTART=0
CURRENT_PID=$PPID

while [ -n "$CURRENT_PID" ] && [ "$CURRENT_PID" -gt 1 ] 2>/dev/null; do
    COMM=$(cat /proc/$CURRENT_PID/comm 2>/dev/null)
    CMD=$(cat /proc/$CURRENT_PID/cmdline 2>/dev/null | tr '\0' ' ')
    case "$COMM $CMD" in
        *vim_app*)
            IS_VIM=1
            break
            ;;
        *autostart*)
            IS_AUTOSTART=1
            break
            ;;
    esac
    CURRENT_PID=$(grep 'PPid:' /proc/$CURRENT_PID/status 2>/dev/null | awk '{print $2}')
done

# 2. Branch according to caller
if [ "$IS_VIM" -eq 1 ]; then
    # vim_app called: Report Board Type 1 -> IUC does not poll u-blox I2C -> Zero DTC B119F:92-08
    exit 1
elif [ "$IS_AUTOSTART" -eq 1 ]; then
    # autostart calls get_board_type.sh twice during boot:
    # - Call 1: checks ublox. Return 1 so autostart itself cleans up ublox.txt
    # - Call 2: starts Service Manager. Return 2 to launch sm_WCP.conf
    FLAG="/tmp/autostart_stage1_done"
    if [ ! -f "$FLAG" ]; then
        touch "$FLAG"
        exit 1
    else
        exit 2
    fi
else
    # libjcimod_eem.so, devmgr, or manual check: Report Board Type 2 -> Enables Wireless CarPlay
    exit 2
fi
EOF
    echo "Updated ${TARGET_SCRIPT} with multi-stage caller-aware DTC fix"
    chmod 0755 "${TARGET_SCRIPT}"
  else
    echo "ERROR: ${TARGET_SCRIPT} not found!"
  fi

  # 2. Clean up any existing ublox.txt
  rm -f /data_persist/ublox.txt 2>/dev/null
  echo "Cleaned up /data_persist/ublox.txt"

  sync
  echo "=== Wireless CarPlay Enable complete ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Wireless CarPlay Enabled successfully!\nDTC B119F fix applied.\nYou can remove the USB drive.\nRebooting in 5 seconds..." --no-cancel &

elif [ $CHOICE -eq 1 ]
then
  # ============================================================
  # DISABLE WIRELESS CARPLAY & RESTORE ORIGINAL
  # ============================================================
  exec > "${MYDIR}/logs/wcp_disable.log" 2>&1
  echo "=== Wireless CarPlay Disable start ==="
  echo "CMU Firmware: V${CMU_VER}"
  echo "Timestamp: $(date)"

  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Disabling Wireless CarPlay...\nRestoring original settings...\nDo not remove USB drive." --no-cancel &

  # 1. Restore get_board_type.sh
  if [ -f "${TARGET_SCRIPT}" ]
  then
    if [ -f "${TARGET_SCRIPT}.orig" ]
    then
      cp -a "${TARGET_SCRIPT}.orig" "${TARGET_SCRIPT}"
      rm -f "${TARGET_SCRIPT}.orig"
      echo "Restored ${TARGET_SCRIPT} from backup"
    else
      echo "WARNING: ${TARGET_SCRIPT}.orig not found, restoring default logic"
      cat << 'EOF' > "${TARGET_SCRIPT}"
#!/bin/sh
ret=1

DI_TP1056=/sys/class/gpio/DI_TP1056/value
DI_TP1029=/sys/class/gpio/DI_TP1029/value

if [ -e "$DI_TP1056" ] && [ -e "$DI_TP1029" ]; then
    for cnt in `seq 0 2`
    do
        value1=$(cat $DI_TP1056)
        if [ $? = '0' ]; then
            if [ $value1 = '0' ] || [ $value1 = '1' ]; then
                value2=$(cat $DI_TP1029)
                if [ $? = '0' ]; then
                    if [ $value2 = '0' ] || [ $value2 = '1' ]; then
                        if [ $value1 = '1' ] || [ $value2 = '1' ]; then
                            ret=2
                        fi
                        break
                    fi
                fi
            fi
        fi
        sleep 1
    done
fi

exit $ret
EOF
    fi
    chmod 0755 "${TARGET_SCRIPT}"
  fi

  # 2. Restore autostart if backup exists from previous versions
  if [ -f "/usr/bin/autostart.orig" ]
  then
    cp -a "/usr/bin/autostart.orig" "/usr/bin/autostart"
    rm -f "/usr/bin/autostart.orig"
    echo "Restored /usr/bin/autostart from backup"
  fi

  # 3. Clean up ublox.txt and tmp flags
  rm -f /data_persist/ublox.txt /tmp/autostart_stage1_done 2>/dev/null

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
