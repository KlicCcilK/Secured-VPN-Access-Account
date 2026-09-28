# VPNAccessPackage

Break-glass local account for domain-joined Windows 11 laptops that only reach the office network through VPN.

Remote users cannot refresh a changed domain password until a tunnel is up. This package creates a locked-down local account, `VPNaccess`, that can start the VPN client, authenticate with domain credentials, and then switch to the real domain profile.

## What it is for

1. Sign in as `VPNaccess`.
2. Start FortiClient from the Start menu and connect with domain credentials.
3. Press Ctrl+Alt+Del → **Switch user** (Ctrl+Alt+End in an RDP session).
4. Sign in to the domain account. The tunnel stays up, so the new password can sync.

`VPNaccess` is a standard local user. It is not an admin account.

## What the lockdown includes

- Assigned Access bound to the `VPNaccess` account only
- Start pin for FortiClient (path detected from the All Users Start Menu)
- Other desktop apps blocked for that account
- Default Outlook (new) taskbar pin hidden
- Notification area / Windows Security tray restricted for `VPNaccess`

Domain users on the same PC are not locked down. Microsoft 365 / classic Outlook is not uninstalled.

## Requirements

- Windows 11
- FortiClient already installed machine-wide (free client is fine)
- Administrator rights to run the installer

No extra tools are required. Assigned Access is applied as SYSTEM through a short-lived scheduled task. Sysinternals PsTools / PsExec is not used and is not a fallback.

## Package contents

| File | Purpose |
|---|---|
| `install.cmd` | Elevated launcher |
| `Install-VpnAccess.ps1` | Creates the account and applies the lockdown |
| `Apply-AssignedAccess.ps1` | Writes Assigned Access as SYSTEM |
| `vpn-restricted-accounts.xml` | Restricted profile |
| `README.md` / `README.txt` | This documentation |
| `LICENSE.txt` | PolyForm Noncommercial License 1.0.0 |

## Install

```text
1. Copy the folder to the target PC.
2. Right-click install.cmd → Run as administrator.
3. Enter the VPNaccess password when prompted.
4. Sign VPNaccess out and back in once before testing.
```

Silent install:

```bat
install.cmd -Password "YourKnownPassword"
```

Remove the Assigned Access profile only (account is left in place):

```bat
install.cmd -RemoveAssignedAccess
```

## What the installer does

- Creates local user `VPNaccess` if it does not exist
- Adds that user to `Users`
- Stages `vpn-restricted-accounts.xml` and `Apply-AssignedAccess.ps1` under `C:\Temp`
- Detects the FortiClient Start Menu shortcut and pins it
- Runs `Apply-AssignedAccess.ps1` as SYSTEM via scheduled task `VPNAccess-ApplyAssignedAccess`, then deletes that task
- Sets machine policies that hide the Outlook (new) default pin
- Sets per-user policies that hide tray / notification UI for `VPNaccess`
- Registers scheduled task `VPNAccess-TrayLockdown` so the tray lockdown is reapplied at `VPNaccess` logon

If the SYSTEM apply task does not return 0, the installer logs a warning and exits with code 1. There is no PsExec retry.

## Logs

- `C:\Temp\vpnaccess-install.log`
- `C:\Temp\apply-assigned-access.log`

## Current VPN support

The profile is built for **FortiClient**. The installer looks for an All Users FortiClient shortcut and allows the FortiClient executables listed in `vpn-restricted-accounts.xml`.

Other VPN clients are not selected automatically. A later revision can detect an already-installed client and generate the allow list and Start pin from that, as long as:

- There is an All Users `.lnk`
- Helper processes are included in AllowedApps
- A standard user can connect using a machine-wide profile

## Notes

- Use the FortiClient tile on Start. The system tray is intentionally limited for this account.
- The FortiClient full GUI can still crash under Assigned Access; the connect flow from the allowed binary is the supported path.
- `DisableCloudOptimizedContent` is machine-wide. It only stops Windows from adding the inbox Outlook (new) pin on new profiles. It does not remove Office.
- Fast user switching is left enabled so you can switch from `VPNaccess` to the domain account after the tunnel is up.
