# Apple Photos Backup to Encrypted Server (iOS)

This project enables automated backup of photos from the Apple Photos app on your iPhone to a crypted folder on a remote server. It leverages Apple Shortcuts, Scriptable, and custom shell scripts to securely transfer and organize your photos using `gocryptfs` encryption. This script heavily relies on the functionality of Apple Shortcut's actions. E.g., the "Find Photos" action not always returns the photo/video in original quality. This is a limitation of that action and this tool can do anything about it. Use this scripts on your own risk.

## Features

- Backup photos from iPhone to a remote encrypted folder
- Uses Apple Shortcuts and Scriptable for automation
- Secure storage with `gocryptfs`
- Metadata and directory structure preserved

## Requirements

- A server (Linux recommended) with SSH access
- `gocryptfs` installed on the server
- Shell scripts from the `bin/` subfolder installed on the server
- iPhone with:
  - Apple Shortcuts app
  - Scriptable app
  - The provided shortcut and Scriptable script

## Installation

### Server Setup

1. **Install gocryptfs**  
   Follow the [gocryptfs installation guide](https://github.com/rfjakob/gocryptfs) for your server OS.

2. **Initialize an encrypted volume**  
   ```sh
   gocryptfs -init /path/to/encrypted-folder
   ```
   Store the passphrase securely; you will need it later.

3. **Install scripts**  
   Copy the contents of the `bin/` subfolder from this repository to the home folder of the backup user on your server and ensure they are executable.

4. **SSH setup**  
   Ensure your server allows SSH connections and you have access to `authorized_keys`.

### iPhone Setup

1. **Import the Shortcut**  
   Add the `Backup Apple Photos.shortcut` to your Shortcuts app.

2. **Configure Shortcut Parameters**  
   Set the server address, username, and any other required parameters in the first section of the shortcut (divided by "Comment" actions).

3. **SSH Key Authentication**  
   In the "Run Script over SSH" action, generate or use an existing public key. Copy this public key to the `authorized_keys` file on your server.

4. **Install Scriptable and Script**  
   - Install the Scriptable app from the App Store.
   - Import `GocryptfsPassphrase.scriptable` into Scriptable.
   - Run the script once and enter the gocryptfs passphrase when prompted. It will be stored securely in the iOS keychain.

### Automation (Optional)

You can trigger the backup shortcut automatically, e.g., when connecting to your home Wi-Fi, using a personal automation in the Shortcuts app.

## Usage

- Run the shortcut manually or let it trigger via automation.
- Photos will be backed up to the encrypted folder on your server.

## Security Notes

- The gocryptfs passphrase is stored securely in the iOS keychain via Scriptable.
- SSH key authentication is used for secure, passwordless access.
- The passphrase for gocryptfs is securely transfered to the server and piped into the command without being saved to disk, but it is in memory on the server and during backup, the crypted volume is mounted on the server.

## License

This project is licensed under the MIT License.  
You are free to use, modify, and distribute this software.  
See the [LICENSE](../LICENSE) file for details.  
**This software is provided "as is", without warranty of any kind. Use at your own risk.**
