# Raspberry Pi USB Mouse Jitter Device

This setup transforms your Raspberry Pi Zero 2W into a USB HID device that automatically jitters the mouse cursor every 10-15 seconds to prevent computers from going to sleep.

## Quick Start

1. **Copy this folder** to your Raspberry Pi Zero 2W desktop
2. **Run the installer** as root:
   ```bash
   sudo chmod +x install.sh
   sudo ./install.sh
   ```
3. **Reboot** when prompted
4. **Connect** Pi to computer via USB data port

## Hardware Requirements

- **Raspberry Pi Zero 2W** (required for USB OTG support)
- **USB cable** (data cable, not power-only)
- **MicroSD card** with Raspberry Pi OS

## How It Works

### USB OTG Mode
The Pi Zero 2W can act as a USB device (rather than host) using USB OTG (On-The-Go) technology. This allows it to appear as a mouse to any computer it's plugged into.

### Mouse Jitter Algorithm
- **Interval**: Random 10-15 seconds between movements
- **Movement**: 1 pixel in random direction, then immediately back
- **Stealth**: Movements are minimal and return to original position

## File Structure

```
raspberry-pi-setup/
├── install.sh                    # Main installation script
├── README.md                     # This file
└── logs/                         # Log files (created after install)
    └── mouse-jitter.log
```

## Installation Details

The installer sets up:

1. **USB OTG Configuration** - Enables dwc2 overlay and libcomposite module
2. **HID Gadget Setup** - Creates USB mouse device at boot
3. **Python Service** - Runs mouse jitter in background
4. **Systemd Services** - Auto-start on boot
5. **Management Scripts** - Easy control commands

## Usage

### Automatic Operation
After installation and reboot, simply plug the Pi into any computer's USB port. The mouse jitter will start automatically.

### Manual Control
```bash
# Check status
mouse-jitter-status

# Start service
mouse-jitter-start

# Stop service  
mouse-jitter-stop
```

### Logs
View real-time logs:
```bash
tail -f /var/log/mouse-jitter.log
```

## Connection Guide

### Correct USB Port
- **Use the USB data port** (usually labeled "USB" not "PWR")
- **NOT the power port** - this won't work for data

### Computer Recognition
When properly connected, the computer will:
- Detect a new USB mouse device
- Show "USB Mouse Jitter" in device manager
- Begin receiving mouse movements every 10-15 seconds

## Troubleshooting

### Pi Not Recognized as Mouse
1. Check you're using the USB data port, not power port
2. Verify Pi Zero 2W model (other Pi models won't work)
3. Check service status: `mouse-jitter-status`
4. Reboot Pi and try again

### Service Not Starting
```bash
# Check service logs
journalctl -u mouse-jitter.service -f

# Check USB gadget setup
lsmod | grep libcomposite
ls /dev/hidg0
```

### Mouse Not Moving
1. Verify HID device exists: `ls -la /dev/hidg0`
2. Check Python script logs: `tail /var/log/mouse-jitter.log`
3. Restart service: `systemctl restart mouse-jitter.service`

## Security Considerations

- **Physical Access**: This device requires physical USB access
- **Detection**: Mouse movements are minimal but detectable
- **Corporate Policy**: Check your organization's policies before use
- **Responsible Use**: Only use on devices you own or have permission to use

## Advanced Configuration

### Modify Timing
Edit `/opt/mouse-jitter/mouse_jitter.py` and change:
```python
# Line ~102: Change interval range
interval = random.uniform(10, 15)  # Modify these values
```

### Change Movement Pattern
Edit the `jitter_mouse()` function to customize movement behavior.

### Disable Auto-Start
```bash
sudo systemctl disable mouse-jitter.service
sudo systemctl disable usb-hid-setup.service
```

## Legal Disclaimer

This tool is for legitimate use cases such as:
- Preventing screen savers during presentations
- Keeping systems active during long processes
- Testing and development purposes

Users are responsible for:
- Compliance with workplace policies
- Obtaining necessary permissions
- Using only on authorized systems

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review log files for error messages
3. Verify hardware compatibility (Pi Zero 2W required)

---

**Note**: This setup modifies system configurations and installs background services. Always test on non-critical systems first.