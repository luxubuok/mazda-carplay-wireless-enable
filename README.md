## Tool to Enable Wireless CarPlay on Older Mazda Vehicles

This tool enables wireless Apple CarPlay on older vehicles that already support wired CarPlay but require a USB cable to connect.

### How It Works

- **Newer vehicle models:** The infotainment system (CMU) in newer models has a minor hardware upgrade to support wireless CarPlay. This tool essentially changes a small configuration parameter so that the CMU in older models recognizes the hardware configuration as compatible with wireless CarPlay, allowing the feature to work without a cable.

- **Wi-Fi limitations on older CMUs:** Older CMUs that only support 2.4 GHz Wi-Fi, without 5 GHz capability, may not provide the smoothest wireless CarPlay experience. This is because 2.4 GHz Wi-Fi offers less bandwidth and is more susceptible to interference than 5 GHz Wi-Fi. However, wireless CarPlay is generally usable in practice. Since usage requirements vary, each user can evaluate the performance based on their own needs and expectations.

- **Compatibility with firmware version 74:** Users running firmware version 74 who have installed certain hacks, such as enabling SSH or removing the startup disclaimer (“No More Disclaimer”), will not be able to use this tool successfully. Even newer vehicles may lose wireless CarPlay functionality if these modifications are installed.

  The reason is that these hacks use system files from older firmware versions (70 or earlier), which do not include wireless CarPlay support.

  **How to fix this:** If you are affected, you must first undo the modifications that caused the issue. The appropriate fix depends on which hacks have been installed. Alternatively, you can reinstall firmware version **74.00.324A**.

Requirements
Firmware version 74.00.324
USB flash drive 32 GB or smaller, formatted as FAT32
Installation / Uninstallation
Extract the zip and copy all files to the root directory of your flash drive.

Safely eject the drive and plug it into your Mazda.

Wait a few seconds for the installer dialog to automatically appear on the screen.

Follow the on-screen prompts to Enable or Disable. Once complete, reboot the head unit.
