# Home Assistant CUPS Print Server App

[![Version](https://img.shields.io/badge/version-1.4.0-blue.svg)](https://github.com/arest/cups-addon)
[![Supports aarch64 Architecture](https://img.shields.io/badge/aarch64-yes-green.svg)](https://github.com/arest/cups-addon)
[![Supports amd64 Architecture](https://img.shields.io/badge/amd64-yes-green.svg)](https://github.com/arest/cups-addon)

This Home Assistant app provides a CUPS (Common Unix Printing System) print server, allowing you to manage and share printers over your local network. It's designed for Home Assistant users who want to integrate network printing capabilities directly into their smart home setup.

## Features

- **Network Printing**: Share printers across your local network using CUPS
- **Web Interface**: Access the CUPS administration panel at `http://<your-ha-ip>:631` to add and manage printers
- **Secure Administration**: Optional authentication for the CUPS admin interface
- **Printer Support**: Compatible with a wide range of network and USB printers
- **Lightweight**: Built on Alpine Linux for minimal resource usage
- **Data Persistence**: Printer settings and configurations persist across restarts and updates

## Installation

### From Home Assistant App Store

1. Navigate to your Home Assistant instance.
2. Go to **Settings** → **Apps** → **Install App**.
3. Click the 3-dot menu in the top right corner and select **Repositories**.
4. Add `https://github.com/arest/cups-addon` as a repository.
5. Find the "CUPS Print Server" app in the store and click it.
6. Click **Install**.

### Manual Installation

If you prefer to manually install:

1. Clone this repository to your local machine:
   ```bash
   git clone https://github.com/arest/cups-addon.git
   ```

2. Copy the repository to your Home Assistant add-ons directory:
   ```bash
   scp -r cups-addon/cups root@<your-ha-ip>:/addons/
   ```

3. In Home Assistant, go to **Settings** → **Apps** → **Install App**.
4. Click the 3-dot menu (top right) → **Repositories**.
5. Add `/addons` as a repository URL and click **Add**.
6. Refresh the app store to see "CUPS Print Server."
7. Install the app.

## Configuration

The app provides the following configuration options:

```yaml
admin_username: printadmin
admin_password: your_secure_password
printer_driver_deb: ""
proxy_printer_name: proxy_printer
proxy_printer_uri: ""
```

- **admin_username**: Username for the CUPS admin interface (default: admin)
- **admin_password**: Password for the CUPS admin interface
- **printer_driver_deb**: Optional `.deb` printer driver stored under `/share`
- **proxy_printer_name**: Name to use when creating an optional local proxy queue (default: `proxy_printer`)
- **proxy_printer_uri**: Optional upstream IPP printer URI to recreate as a local, shareable queue, for example `ipp://192.168.1.52:631/printers/DCPT230`

After configuring:

1. Start the app from the Info tab.
2. Check the Log tab to ensure it starts successfully.
3. Access the CUPS web interface at `http://<your-ha-ip>:631`.

## Usage

### Access the Web Interface

Visit `http://<your-ha-ip>:631` in your browser.

### Add a Printer

1. Go to the **Administration** tab.
2. Click **Add Printer** and follow the prompts.
3. Select the appropriate driver for your printer model.

### Print from Devices

Configure your computers or devices to use the printer at `<your-ha-ip>:631`.

### Re-share a Remote IPP/CUPS Printer

If CUPS shows `Cannot change printer-is-shared for remote queues`, the printer was added as a remote/discovered queue. The web UI cannot make that queue shared. Configure the add-on to recreate it as a permanent local proxy queue instead:

```yaml
proxy_printer_name: proxy_printer
proxy_printer_uri: ipp://192.168.1.52:631/printers/DCPT230
```

On startup, the add-on removes any existing queue with that name, creates a local IPP Everywhere queue that forwards jobs to the upstream URI, enables sharing for the local queue, accepts jobs, and sets it as the default printer.

Clients can then print through this add-on at:

```text
ipp://<home-assistant-ip>:631/printers/proxy_printer
```


## Supported Printer Types

This app supports various printer types:

- Network printers (via IPP, LPD, etc.)
- USB printers connected to your Home Assistant host
- Shared Windows printers (via Samba)
- AirPrint for Apple devices

## Troubleshooting

### Can't Access Web Interface

- Ensure the app is running (check logs).
- Verify port 631 isn't blocked by your firewall.
- Check that your network allows access to the Home Assistant device.

### Printer Not Detected

- Ensure the printer is network-accessible or connected via USB to the host.
- For USB printers, you may need to configure USB device pass-through to the app.
- Check CUPS logs in the app's Log tab.


### Printer Drivers
   https://www.openprinting.org/download/PPD/
   https://www.openprinting.org/drivers/

### Authentication Issues

- Verify you're using the correct username and password configured in the app settings.
- If you've forgotten your password, you can reset it by reconfiguring the app.

## Contributing

Contributions are welcome! Please:

1. Fork this repository.
2. Create a feature branch (`git checkout -b feature/your-feature`).
3. Commit your changes (`git commit -m "Add your feature"`).
4. Push to the branch (`git push origin feature/your-feature`).
5. Open a pull request.

## License

This project is licensed under the MIT License.

## Credits

- Built by [Andrea Restello](https://github.com/arest)
- Powered by [Home Assistant](https://www.home-assistant.io/) and [CUPS](https://www.cups.org/)

## Data Persistence

This app stores all CUPS data in the Home Assistant `/data` directory, ensuring:

- Printer configurations persist across app restarts
- Print jobs and settings are maintained through system reboots
- App updates won't cause loss of printer configurations
- All CUPS data is included in Home Assistant backups

The following directories are maintained in the persistent storage:
- `/data/cups/config`: CUPS configuration files
- `/data/cups/cache`: CUPS cache data
- `/data/cups/logs`: CUPS log files
- `/data/cups/state`: CUPS state information

