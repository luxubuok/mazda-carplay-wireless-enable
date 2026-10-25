#!/bin/sh
# Wireless CarPlay Enabler/Disabler for Mazda CMU
# Target CMU Firmware: V74.x (e.g. 74.00.324)
# Features:
#   1. Wireless CarPlay activation (FW 74)
#   2. Zero DTC B119F:92-08 (Smart caller-aware get_board_type.sh)
#   3. Anti-bootloop & Anti-reboot patch for sm_WCP.conf (jciLDS & jcinavi)
#   4. Fail-safe kill-switch support (/data_persist/wcp_force_off)

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
SM_WCP_CONF="/jci/sm/sm_WCP.conf"

# --- Prompt user: Enable, Disable, or Cancel ---
/jci/tools/jci-dialog --3-button-dialog \
  --title="Wireless CarPlay" \
  --text="Enable or Disable Wireless CarPlay?\nDetected CMU FW: V${CMU_VER}\nIncludes DTC B119F Fix & Anti-Reboot Patch" \
  --ok-label="Enable" \
  --cancel-label="Disable" \
  --button3-label="Cancel"
CHOICE=$?

if [ $CHOICE -eq 0 ]
then
  # ============================================================
  # ENABLE WIRELESS CARPLAY + DTC B119F FIX + ANTI-REBOOT PATCH
  # ============================================================
  exec > "${MYDIR}/logs/wcp_enable.log" 2>&1
  echo "=== Wireless CarPlay Enable start ==="
  echo "CMU Firmware: V${CMU_VER}"
  echo "Timestamp: $(date)"

  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Enabling Wireless CarPlay...\nApplying DTC fix & anti-reboot patch...\nDo not remove USB drive." --no-cancel &

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

# Safety kill-switch (Force Disable Wireless CarPlay if needed)
if [ -e /data_persist/wcp_force_off ]; then
    exit 1
fi

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
    # - Call 2: starts Service Manager. Delete flag & return 2 to launch sm_WCP.conf
    FLAG="/tmp/autostart_stage1_done"
    if [ ! -f "$FLAG" ]; then
        touch "$FLAG"
        exit 1
    else
        rm -f "$FLAG"
        exit 2
    fi
else
    # libjcimod_eem.so, devmgr, or manual check: Report Board Type 2 -> Enables Wireless CarPlay
    exit 2
fi
EOF
    echo "Updated ${TARGET_SCRIPT} with self-cleaning multi-stage DTC fix"
    chmod 0755 "${TARGET_SCRIPT}"
  else
    echo "ERROR: ${TARGET_SCRIPT} not found!"
  fi

  # 2. Patch sm_WCP.conf (Disable UBLOX checks and remove reset_board="yes" to prevent reboot loop)
  if [ -f "${SM_WCP_CONF}" ]
  then
    if [ ! -f "${SM_WCP_CONF}.orig" ]
    then
      cp -a "${SM_WCP_CONF}" "${SM_WCP_CONF}.orig"
      echo "Created backup: ${SM_WCP_CONF}.orig"
    else
      echo "Backup ${SM_WCP_CONF}.orig already exists"
    fi

    # Remove GPS=UBLOX from jciLDS and prevent board reset on failure
    sed -i '/name="jciLDS"/s/ GPS=UBLOX//' "${SM_WCP_CONF}"
    sed -i '/name="jciLDS"/s/reset_board="yes"/reset_board="no"/' "${SM_WCP_CONF}"

    # Return jcinavi to default GPS chip (STA8) and prevent board reset on failure
    sed -i '/name="jcinavi"/s/args="wcp"/args=""/' "${SM_WCP_CONF}"
    sed -i '/name="jcinavi"/s/reset_board="yes"/reset_board="no"/' "${SM_WCP_CONF}"

    echo "Patched ${SM_WCP_CONF}: neutralized UBLOX & disabled reset_board on jciLDS/jcinavi"
    chmod 0644 "${SM_WCP_CONF}"
  fi

  # 3. Clean up any existing ublox.txt or force-off flags
  rm -f /data_persist/ublox.txt /data_persist/wcp_force_off 2>/dev/null
  echo "Cleaned up /data_persist/ublox.txt"

  sync
  echo "=== Wireless CarPlay Enable complete ==="

  killall -q jci-dialog
  /jci/tools/jci-dialog --info --title="Wireless CarPlay" \
    --text="Wireless CarPlay Enabled successfully!\nDTC B119F fix & anti-reboot patch applied.\nYou can remove the USB drive.\nRebooting in 5 seconds..." --no-cancel &

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

  # 2. Restore sm_WCP.conf
  if [ -f "${SM_WCP_CONF}" ]
  then
    if [ -f "${SM_WCP_CONF}.orig" ]
    then
      cp -a "${SM_WCP_CONF}.orig" "${SM_WCP_CONF}"
      rm -f "${SM_WCP_CONF}.orig"
      echo "Restored ${SM_WCP_CONF} from backup"
    fi
    chmod 0644 "${SM_WCP_CONF}"
  fi

  # 3. Clean up ublox.txt, wcp_force_off and tmp flags
  rm -f /data_persist/ublox.txt /data_persist/wcp_force_off /tmp/autostart_stage1_done 2>/dev/null

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
