# Apple Photos Backup for macOS

This toolset enables automated export and backup of photos and videos in original quality from the Apple Photos app on a Mac, even when Advanced Data Protection (ADP) is enabled for iCloud and "Optimize Mac Storage" is active. All scripts are executed locally on the Mac and are designed to work reliably with optimized and encrypted photo libraries.

## Features

- Exports original photos and videos from Apple Photos using [osxphotos](https://github.com/RhetTbull/osxphotos)
- Handles optimized libraries and ADP-protected iCloud Photos
- Organizes exports by date and preserves metadata
- Syncs exported files to a remote encrypted folder via SSHFS and [gocryptfs](https://github.com/rfjakob/gocryptfs)
- Automated periodic backups using a launchd job (`com.user.trigger_backup_photos.plist`)
- Configurable via a single config file (`photos_backup.conf`)

## Folder Structure

- `bin/` — Shell scripts for export, sync, and backup
- `photos_backup.conf` — Main configuration file (user-specific, not in version control)
- `photos_backup.conf.template` — Template for configuration
- `com.user.trigger_backup_photos.plist` — launchd job for automation

## Requirements

- macOS with Apple Photos and iCloud Photos enabled
- [osxphotos](https://github.com/RhetTbull/osxphotos) (Python package)
- [gocryptfs](https://github.com/rfjakob/gocryptfs) (installed via Homebrew or similar)
- [sshfs](https://osxfuse.github.io/) (installed via Homebrew)
- SSH access to a remote server for encrypted backup storage

## Installation

1. **Install dependencies:**
   ```sh
   brew install gocryptfs sshfs
   pip install osxphotos
   ```

2. **Copy and configure:**
   - Copy `photos_backup.conf.template` to `photos_backup.conf` and edit the values to match your environment (SSH user, host, paths, etc.).

3. **Set up gocryptfs on the remote server:**
   - Initialize an encrypted volume on your server using `gocryptfs -init`.
   - Store the passphrase securely.

### Store gocryptfs Passphrase in macOS Keychain

The gocryptfs passphrase must be stored in the macOS Keychain so that the scripts can mount the encrypted volume automatically.  
**Keychain entry name:** Use the value of `KEYCHAIN_SERVICE` from your `photos_backup.conf` (default: `photos_backup`).

To add the passphrase:

```sh
security add-generic-password -a "$USER" -s photos_backup -w
```

You will be prompted to enter the passphrase.  
- `-s photos_backup` sets the service name (must match `KEYCHAIN_SERVICE` in your config).
- The passphrase will be securely stored and accessed by the scripts.

### Install osxphotos using a virtual environment

macOS restricts system Python. Use a virtual environment to install osxphotos:

```sh
# 1. Create virtual environment
python3 -m venv ~/osxphotos-env

# 2. Activate it
source ~/osxphotos-env/bin/activate

# 3. Install osxphotos
pip install osxphotos
```

If you use osxphotos regularly, create a wrapper script (already included as `bin/osxphotos.sh`):

```bash
#!/bin/bash
source ~/osxphotos-env/bin/activate
osxphotos "$@"
```

This keeps your system Python untouched and allows full use of osxphotos.

4. **Automate backups (optional):**
   - Copy `com.user.trigger_backup_photos.plist` to `~/Library/LaunchAgents/`.
   - Load the job with:
     ```sh
     launchctl load ~/Library/LaunchAgents/com.user.trigger_backup_photos.plist
     ```

## Usage

- **Manual backup:**  
  Run the main backup script:
  ```sh
  ./bin/backup_photos.sh
  ```
  This will:
  - Mount the remote encrypted folder via SSHFS
  - Mount the decrypted gocryptfs volume
  - Export new/modified photos and videos since the last backup
  - Sync them to the encrypted remote folder
  - Unmount everything

- **Automated backup:**  
  The launchd job (`com.user.trigger_backup_photos.plist`) will trigger the backup every 5 minutes by default.

## Configuration

Edit `photos_backup.conf` to set:
- SSH connection details
- Remote and local mount points
- Export directories
- Date threshold for incremental backups
- Keychain service for storing the gocryptfs passphrase

See `photos_backup.conf.template` for all available options.

## Security Notes

- The gocryptfs passphrase is stored in the macOS Keychain.
- SSH key authentication is used for secure, passwordless access.
- Backups are encrypted at rest on the remote server.

## License

This project is licensed under the MIT License.  
You are free to use, modify, and distribute this software.  
See the [LICENSE](../LICENSE) file for details.  
**This software is provided "as is", without warranty of any kind. Use at your own risk.**
