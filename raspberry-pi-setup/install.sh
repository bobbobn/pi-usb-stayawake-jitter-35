#!/bin/bash

# Raspberry Pi USB Mouse Jitter Auto-Installer
# This script sets up a Raspberry Pi Zero 2W as a USB HID device
# that jitters the mouse every 10-15 seconds to keep computers awake

echo "=== Raspberry Pi USB Mouse Jitter Setup ==="
echo "This will configure your Pi Zero 2W as a USB HID mouse device"
echo ""

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo "Please run as root (use sudo)"
    exit 1
fi

# Check if this is a Pi Zero (required for USB OTG)
if ! grep -q "Raspberry Pi Zero" /proc/cpuinfo && ! grep -q "Raspberry Pi Zero 2" /proc/cpuinfo; then
    echo "Warning: This script is designed for Raspberry Pi Zero/Zero 2W"
    echo "Other Pi models may not support USB OTG mode"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

echo "Step 1: Updating system packages..."
apt update && apt upgrade -y

echo "Step 2: Installing required packages..."
apt install -y python3 python3-pip git

echo "Step 3: Enabling dwc2 overlay for USB OTG..."
# Enable dwc2 overlay in config.txt
if ! grep -q "dtoverlay=dwc2" /boot/firmware/config.txt; then
    echo "dtoverlay=dwc2" >> /boot/firmware/config.txt
fi

echo "Step 4: Adding libcomposite to modules..."
# Add libcomposite module
if ! grep -q "libcomposite" /etc/modules; then
    echo "libcomposite" >> /etc/modules
fi

echo "Step 5: Creating USB HID gadget setup script..."
# Create the USB gadget setup script
cat > /usr/local/bin/setup-usb-hid.sh << 'EOF'
#!/bin/bash

# Remove existing gadget if it exists
if [ -d "/sys/kernel/config/usb_gadget/mouse_jitter" ]; then
    echo "Removing existing USB gadget..."
    echo "" > /sys/kernel/config/usb_gadget/mouse_jitter/UDC
    rm -rf /sys/kernel/config/usb_gadget/mouse_jitter
fi

# Wait a moment
sleep 2

# Create gadget directory
mkdir -p /sys/kernel/config/usb_gadget/mouse_jitter
cd /sys/kernel/config/usb_gadget/mouse_jitter

# Set USB device information
echo 0x1d6b > idVendor  # Linux Foundation
echo 0x0104 > idProduct # Multifunction Composite Gadget
echo 0x0100 > bcdDevice # v1.0.0
echo 0x0200 > bcdUSB    # USB2

# Create strings
mkdir -p strings/0x409
echo "fedcba9876543210" > strings/0x409/serialnumber
echo "Mouse Jitter Device" > strings/0x409/manufacturer
echo "USB Mouse Jitter" > strings/0x409/product

# Create configuration
mkdir -p configs/c.1/strings/0x409
echo "Config 1: HID Mouse" > configs/c.1/strings/0x409/configuration
echo 250 > configs/c.1/MaxPower

# Create HID function (mouse)
mkdir -p functions/hid.usb0
echo 1 > functions/hid.usb0/protocol   # Mouse
echo 1 > functions/hid.usb0/subclass  # Boot interface subclass
echo 3 > functions/hid.usb0/report_length

# HID Report Descriptor for a standard mouse
echo -ne \\x05\\x01\\x09\\x02\\xa1\\x01\\x09\\x01\\xa1\\x00\\x05\\x09\\x19\\x01\\x29\\x03\\x15\\x00\\x25\\x01\\x95\\x03\\x75\\x01\\x81\\x02\\x95\\x01\\x75\\x05\\x81\\x03\\x05\\x01\\x09\\x30\\x09\\x31\\x15\\x81\\x25\\x7f\\x75\\x08\\x95\\x02\\x81\\x06\\xc0\\xc0 > functions/hid.usb0/report_desc

# Link function to configuration
ln -s functions/hid.usb0 configs/c.1/

# Find UDC and enable gadget
UDC=$(ls /sys/class/udc | head -n1)
echo $UDC > UDC

echo "USB HID gadget created successfully"
EOF

chmod +x /usr/local/bin/setup-usb-hid.sh

echo "Step 6: Creating mouse jitter Python script..."
# Create the mouse jitter script
mkdir -p /opt/mouse-jitter
cat > /opt/mouse-jitter/mouse_jitter.py << 'EOF'
#!/usr/bin/env python3
"""
USB Mouse Jitter Script for Raspberry Pi
Moves mouse by 1 pixel every 10-15 seconds to prevent computer sleep
"""

import time
import random
import logging
import signal
import sys
import os

# Set up logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s',
    handlers=[
        logging.FileHandler('/var/log/mouse-jitter.log'),
        logging.StreamHandler()
    ]
)

class MouseJitter:
    def __init__(self, device_path='/dev/hidg0'):
        self.device_path = device_path
        self.running = True
        self.device = None
        
        # Set up signal handlers for graceful shutdown
        signal.signal(signal.SIGINT, self.signal_handler)
        signal.signal(signal.SIGTERM, self.signal_handler)
        
    def signal_handler(self, signum, frame):
        """Handle shutdown signals gracefully"""
        logging.info(f"Received signal {signum}, shutting down...")
        self.running = False
        if self.device:
            self.device.close()
        sys.exit(0)
    
    def wait_for_device(self, timeout=30):
        """Wait for HID device to become available"""
        logging.info(f"Waiting for HID device {self.device_path}...")
        start_time = time.time()
        
        while time.time() - start_time < timeout:
            if os.path.exists(self.device_path):
                try:
                    self.device = open(self.device_path, 'wb')
                    logging.info("HID device connected successfully")
                    return True
                except Exception as e:
                    logging.warning(f"Failed to open device: {e}")
                    time.sleep(1)
            time.sleep(1)
        
        logging.error(f"Timeout waiting for HID device {self.device_path}")
        return False
    
    def send_mouse_report(self, x_delta=0, y_delta=0, buttons=0):
        """Send a mouse HID report"""
        if not self.device:
            return False
            
        try:
            # Convert signed deltas to unsigned bytes
            x_byte = x_delta & 0xFF if x_delta >= 0 else (256 + x_delta) & 0xFF
            y_byte = y_delta & 0xFF if y_delta >= 0 else (256 + y_delta) & 0xFF
            
            # HID report: [buttons, x_delta, y_delta]
            report = bytes([buttons, x_byte, y_byte])
            self.device.write(report)
            self.device.flush()
            return True
        except Exception as e:
            logging.error(f"Failed to send mouse report: {e}")
            return False
    
    def move_circle(self, radius=10, steps=20):
        """Move mouse in a circle to indicate the service is working"""
        logging.info("Moving mouse in circle to indicate service is active...")
        import math
        
        for i in range(steps):
            angle = 2 * math.pi * i / steps
            x = int(radius * math.cos(angle))
            y = int(radius * math.sin(angle))
            
            if self.send_mouse_report(x_delta=x, y_delta=y):
                logging.debug(f"Circle movement step {i+1}/{steps}: ({x}, {y})")
                time.sleep(0.1)
        
        # Return to center with final movement
        self.send_mouse_report(x_delta=0, y_delta=0)
        logging.info("Circle movement complete - service is working!")

    def jitter_mouse(self):
        """Move mouse by 1 pixel in a random direction, then back"""
        # Random direction (1 or -1 for x and y)
        x_dir = random.choice([-1, 1])
        y_dir = random.choice([-1, 1])
        
        # Move mouse by 1 pixel
        if self.send_mouse_report(x_delta=x_dir, y_delta=y_dir):
            logging.debug(f"Mouse moved by ({x_dir}, {y_dir})")
            
            # Small delay
            time.sleep(0.1)
            
            # Move back to original position
            if self.send_mouse_report(x_delta=-x_dir, y_delta=-y_dir):
                logging.debug(f"Mouse returned to original position")
                return True
        
        return False
    
    def run(self):
        """Main loop"""
        logging.info("Starting mouse jitter service...")
        
        # Wait for HID device
        if not self.wait_for_device():
            logging.error("Failed to connect to HID device, exiting")
            return
        
        logging.info("Mouse jitter service started successfully")
        
        # Move in circle at startup to show it's working
        self.move_circle()
        
        while self.running:
            try:
                # Random interval between 10-15 seconds
                interval = random.uniform(10, 15)
                logging.info(f"Waiting {interval:.1f} seconds until next jitter...")
                
                # Sleep in small chunks to allow for responsive shutdown
                elapsed = 0
                while elapsed < interval and self.running:
                    time.sleep(0.5)
                    elapsed += 0.5
                
                if self.running:
                    if self.jitter_mouse():
                        logging.info("Mouse jitter successful")
                    else:
                        logging.warning("Mouse jitter failed")
                        
            except Exception as e:
                logging.error(f"Error in main loop: {e}")
                time.sleep(5)  # Wait before retrying

if __name__ == "__main__":
    jitter = MouseJitter()
    jitter.run()
EOF

chmod +x /opt/mouse-jitter/mouse_jitter.py

echo "Step 7: Creating systemd services..."

# Create service for USB HID setup
cat > /etc/systemd/system/usb-hid-setup.service << 'EOF'
[Unit]
Description=Setup USB HID Gadget
After=multi-user.target
Wants=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/setup-usb-hid.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

# Create service for mouse jitter
cat > /etc/systemd/system/mouse-jitter.service << 'EOF'
[Unit]
Description=USB Mouse Jitter Service
After=usb-hid-setup.service
Requires=usb-hid-setup.service
StartLimitIntervalSec=0

[Service]
Type=simple
ExecStart=/usr/bin/python3 /opt/mouse-jitter/mouse_jitter.py
Restart=always
RestartSec=10
User=root
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

echo "Step 8: Enabling services..."
systemctl daemon-reload
systemctl enable usb-hid-setup.service
systemctl enable mouse-jitter.service

echo "Step 9: Creating management scripts..."

# Create start script
cat > /usr/local/bin/mouse-jitter-start << 'EOF'
#!/bin/bash
echo "Starting mouse jitter service..."
systemctl start usb-hid-setup.service
systemctl start mouse-jitter.service
systemctl status mouse-jitter.service
EOF
chmod +x /usr/local/bin/mouse-jitter-start

# Create stop script
cat > /usr/local/bin/mouse-jitter-stop << 'EOF'
#!/bin/bash
echo "Stopping mouse jitter service..."
systemctl stop mouse-jitter.service
systemctl status mouse-jitter.service
EOF
chmod +x /usr/local/bin/mouse-jitter-stop

# Create status script
cat > /usr/local/bin/mouse-jitter-status << 'EOF'
#!/bin/bash
echo "=== USB HID Setup Service ==="
systemctl status usb-hid-setup.service
echo ""
echo "=== Mouse Jitter Service ==="
systemctl status mouse-jitter.service
echo ""
echo "=== Recent Logs ==="
journalctl -u mouse-jitter.service -n 20 --no-pager
EOF
chmod +x /usr/local/bin/mouse-jitter-status

echo ""
echo "=== Installation Complete! ==="
echo ""
echo "The system is now configured to act as a USB mouse jitter device."
echo ""
echo "IMPORTANT: You need to REBOOT for all changes to take effect!"
echo ""
echo "After reboot:"
echo "- Connect your Pi Zero to a computer via the USB data port (not power port)"
echo "- The Pi will appear as a USB mouse device"
echo "- Mouse will jitter every 10-15 seconds automatically"
echo ""
echo "Management commands:"
echo "- mouse-jitter-start  : Start the service"
echo "- mouse-jitter-stop   : Stop the service" 
echo "- mouse-jitter-status : Check service status and logs"
echo ""
echo "Log file: /var/log/mouse-jitter.log"
echo ""
read -p "Reboot now? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "Rebooting in 3 seconds..."
    sleep 3
    reboot
else
    echo "Remember to reboot before using the device!"
fi