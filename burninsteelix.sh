#!/bin/bash

# Ensure the script is run as root
if [ "$EUID" -ne 0 ]; then
  echo "❌ Error: Please run this script with sudo (e.g., sudo bash deploy_repair.sh)"
  exit 1
fi
# Update the download path inside your burninsteelix.sh script to look like this:
if [ ! -f "bios.bin" ]; then
  echo "📥 Downloading bios.bin from repository..."
  curl -L -o bios.bin "https://raw.githubusercontent.com/omegadraco-wps/steelix_recovery/main/bios.bin"
fi

DONOR_FILE="bios.bin"
WORKING_FILE="machine_ready.bin"

echo "================================================="
echo "   Automated Chromebook Identity Deployment      "
echo "================================================="

# 1. Check if the donor BIOS file exists in the current directory
if [ ! -f "$DONOR_FILE" ]; then
  echo "❌ Error: $DONOR_FILE not found in the current directory!"
  echo "Make sure your good BIOS dump is named '$DONOR_FILE' and sits next to this script."
  exit 1
fi

# 2. Read the target machine's current firmware to extract its unique system serial number
echo "🔄 Reading target machine's current identity..."
sudo flashrom -r target_broken.bin

if [ ! -f "target_broken.bin" ]; then
  echo "❌ Error: Failed to read the target chip firmware."
  exit 1
fi

TARGET_SN=$(sudo vpd -f target_broken.bin -i RO_VPD -g serial_number)

if [ -z "$TARGET_SN" ]; then
  echo "⚠️ Warning: Could not extract native serial number automatically."
  read -p "👉 Please enter the Serial Number manually: " TARGET_SN
  TARGET_SN=$(echo "$TARGET_SN" | tr -d ' ' | tr '[:lower:]' '[:upper:]')
fi

echo "✅ Target Serial Number Identified: $TARGET_SN"

# 3. Prepare the fresh deployment file
cp "$DONOR_FILE" "$WORKING_FILE"

# 4. Inject the correct serial number and purge the donor's bad attestation fields
echo "⚙️  Injecting target serial and purging old attestation data..."
sudo vpd -f "$WORKING_FILE" -i RO_VPD -s "serial_number"="$TARGET_SN"
sudo vpd -f "$WORKING_FILE" -i RO_VPD -d attested_device_id

# 5. Disable Software Write-Protection on the chip
echo "🔓 Disabling software write-protection..."
sudo flashrom --wp-disable

# 6. Flash the fully customized, clean image to the chip
echo "🚀 Flashing the motherboard..."
sudo flashrom -w "$WORKING_FILE"

if [ $? -eq 0 ]; then
  echo "================================================="
  echo "✅ SUCCESS: Firmware flashed and identity prepared!"
  echo "================================================="
  # Request TPM wipe on next boot to sync the new identity
  sudo crossystem clear_tpm_owner_request=1
  echo "Shut down the machine, boot to Recovery Mode (Esc+Refresh+Power),"
  echo "and run a full ChromeOS USB restoration to generate the new ADID."
  echo "================================================="
else
  echo "❌ Error: Flashrom failed to write to the chip."
  echo "Verify that hardware write-protection (battery/jumper) is completely disabled."
fi

# Clean up temporary execution files
rm -f target_broken.bin "$WORKING_FILE"