# Apple Photos Backup for macOS

This toolset automates the export and encrypted backup of photos and videos from the Apple Photos app on your Mac. It enables regular, incremental backups in original quality—even when iCloud Advanced Data Protection (ADP) and "Optimize Mac Storage" are enabled. Photos are exported locally, synchronized in encrypted form to a remote server, and regularly versioned using [BorgBackup](https://www.borgbackup.org/). All orchestration is handled by shell scripts designed for reliability and automation on macOS.

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
- [gocryptfs](https://github.com/rfjakob/gocryptfs) (via Homebrew or similar)
- [sshfs](https://osxfuse.github.io/) (via Homebrew)
- [borgbackup](https://www.borgbackup.org/) (recommended: Homebrew-tapped version with FUSE support, see below)
- SSH access to a remote server for encrypted backups

**Note on BorgBackup:**  
For automatic pruning and mounting of archives, Borg with FUSE support is required.  
It is recommended to install the tapped Homebrew version:
```sh
brew install borgbackup/tap/borgbackup-fuse
```
Alternatively:
```sh
brew install borgbackup
```
The tapped version (`borgbackup-fuse`) includes FUSE bindings and is recommended for macOS.

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

4. **Automate backups (optional):**
   - Copy `com.user.trigger_backup_photos.plist` to `~/Library/LaunchAgents/`.
   - The script expects `trigger_backup_photos.sh` in `/usr/local/bin`, so either make a symbolic link with `ln -s` or change the location in the `plist`.
   - Load the job with:
     ```sh
     launchctl load ~/Library/LaunchAgents/com.user.trigger_backup_photos.plist
     ```

### Store gocryptfs and Borg Passphrases in macOS Keychain

The gocryptfs and Borg passphrases must be stored in the macOS Keychain so that the scripts can mount the encrypted volume and run backups automatically.  
**Keychain entry names:** Use the values of `GOCRYPTFS_KEYCHAIN` and `BORG_KEYCHAIN` from your `photos_backup.conf` (defaults: `gocryptfs_photos_backup` and `borg_photos_backup`).

To add the gocryptfs passphrase:

```sh
security add-generic-password -a "$USER" -s gocryptfs_photos_backup -w
```

To add the Borg passphrase:

```sh
security add-generic-password -a "$USER" -s borg_photos_backup -w
```

You will be prompted to enter the passphrases.  
- `-s gocryptfs_photos_backup` and `-s borg_photos_backup` set the service names (must match `GOCRYPTFS_KEYCHAIN` and `BORG_KEYCHAIN` in your config).
- The passphrases will be securely stored and accessed by the scripts.

#### Using Long Passphrases with Borg (Keychain Split Logic)

If your Borg passphrase is very long or you want to split it for security reasons, you can store it in two separate macOS Keychain entries. The script will concatenate both entries automatically:

- The main entry uses the value of `BORG_KEYCHAIN` (e.g., `borg_photos_backup`).
- The second part should be stored in a keychain entry with the same name plus `_1` (e.g., `borg_photos_backup_1`).

The script will read both entries and concatenate them to form the full passphrase. If the `_1` entry does not exist, only the main entry is used.

Example to add both parts:
```sh
security add-generic-password -a "$USER" -s borg_photos_backup -w
security add-generic-password -a "$USER" -s borg_photos_backup_1 -w
```

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
- During execution the script may ask for permission for `python3` to access the file system. You can add via drag&drop the executable to the privacy settings in `system settings`. If `python3` is a symbolic link, it might be necessary to look up the link target (so the binary) and give it the permission to access the file system instead of the symbolic link.

See `photos_backup.conf.template` for all available options.

## Security Notes

- The gocryptfs passphrase is stored in the macOS Keychain.
- SSH key authentication is used for secure, passwordless access (via `ssh-agent`).
- Backups are encrypted at rest on the remote server.

## Troubleshooting: launchctl and LaunchAgents

If loading the LaunchAgent with `launchctl load ~/Library/LaunchAgents/com.user.trigger_backup_photos.plist` does not work (e.g., due to permission issues), you can try loading it as root for your user session:

```sh
sudo launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.user.trigger_backup_photos.plist
```

A reboot can also help if you encounter persistent issues with LaunchAgents not starting as expected.

**Note:**  
LaunchAgents do not run in a fully configured user environment as you would expect in a Terminal session. This can lead to permission or environment issues, especially when working with filesystems mounted via macFUSE (e.g., gocryptfs).  
For example, writing directly into the decrypted gocryptfs directory from a LaunchAgent may fail due to macOS sandboxing or FUSE permission restrictions. Using `rsync` for file operations has proven more reliable in this context, which is why the scripts use `rsync` for syncing and deleting files.

If you encounter permission problems or other issues related to LaunchAgents and file access, please open an issue in the repository with details about your setup and the error.

## License

This project is licensed under the MIT License.  
You are free to use, modify, and distribute this software.  
See the [LICENSE](../LICENSE) file for details.  
**This software is provided "as is", without warranty of any kind. Use at your own risk.**
