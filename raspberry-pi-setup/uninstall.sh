#!/bin/bash

# Raspberry Pi USB Mouse Jitter Uninstaller
# This script removes all components installed by the mouse jitter setup

echo "=== Raspberry Pi USB Mouse Jitter Uninstaller ==="
echo "This will remove all mouse jitter components from your system"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

read -p "Are you sure you want to uninstall? This cannot be undone. (y/N): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo "Step 1: Stopping and disabling services..."
systemctl stop mouse-jitter.service 2>/dev/null
systemctl stop usb-hid-setup.service 2>/dev/null
systemctl disable mouse-jitter.service 2>/dev/null
systemctl disable usb-hid-setup.service 2>/dev/null

echo "Step 2: Removing systemd service files..."
rm -f /etc/systemd/system/mouse-jitter.service
rm -f /etc/systemd/system/usb-hid-setup.service
systemctl daemon-reload

echo "Step 3: Removing USB gadget..."
if [ -d "/sys/kernel/config/usb_gadget/mouse_jitter" ]; then
    echo "" > /sys/kernel/config/usb_gadget/mouse_jitter/UDC 2>/dev/null
    rm -rf /sys/kernel/config/usb_gadget/mouse_jitter 2>/dev/null
fi

echo "Step 4: Removing installed files..."
rm -rf /opt/mouse-jitter
rm -f /usr/local/bin/setup-usb-hid.sh
rm -f /usr/local/bin/mouse-jitter-start
rm -f /usr/local/bin/mouse-jitter-stop
rm -f /usr/local/bin/mouse-jitter-status

echo "Step 5: Removing log files..."
rm -f /var/log/mouse-jitter.log

echo "Step 6: Cleaning up system configuration..."
# Remove libcomposite from /etc/modules
sed -i '/^libcomposite$/d' /etc/modules

# Remove dwc2 overlay from config.txt (ask user)
if grep -q "dtoverlay=dwc2" /boot/firmware/config.txt; then
    echo ""
    echo "Found dwc2 overlay in /boot/firmware/config.txt"
    read -p "Remove dwc2 overlay? This will disable USB OTG. (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sed -i '/^dtoverlay=dwc2$/d' /boot/firmware/config.txt
        echo "Removed dwc2 overlay from config.txt"
    else
        echo "Kept dwc2 overlay in config.txt"
    fi
fi

echo ""
echo "=== Uninstall Complete! ==="
echo ""
echo "All mouse jitter components have been removed."
echo ""
echo "Note: A reboot is recommended to ensure all changes take effect."
echo ""
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    echo "Remember to reboot to complete the removal!"
fi