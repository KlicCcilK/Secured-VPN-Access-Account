VPN break-glass package
=======================

Contents
- install.cmd                 Double-click this after unzipping
- Install-VpnAccess.ps1       Main installer
- Apply-AssignedAccess.ps1    Applies the Assigned Access XML as SYSTEM
- vpn-restricted-accounts.xml Restricted profile for the VPNaccess account
- README.md / README.txt      Documentation
- LICENSE.txt                 PolyForm Noncommercial License 1.0.0

No extra downloads are required. PsTools / PsExec is not used.

How to install
1. Unzip the package on the target PC.
2. Right-click install.cmd -> Run as administrator
   (or double-click; it will prompt for elevation).
3. When asked, enter the VPNaccess password.
4. Sign out of VPNaccess or reboot, then test.

Silent password example
  install.cmd -Password "YourKnownPassword"

Remove Assigned Access only
  install.cmd -RemoveAssignedAccess

What the installer does
- Creates local user VPNaccess if missing
- Adds VPNaccess to Users
- Creates C:\Temp if needed
- Copies the XML and apply script to C:\Temp
- Applies Assigned Access as SYSTEM through scheduled task
  VPNAccess-ApplyAssignedAccess, then removes that task
- Hides the Outlook (new) taskbar pin
- Applies tray / notification lockdown for VPNaccess
- Registers scheduled task VPNAccess-TrayLockdown at VPNaccess logon
- Does not AppLocker-deny OUTLOOK.EXE or deprovision Office
- Does not install or extract PsTools

If the SYSTEM apply task fails, the installer exits with code 1.
There is no PsExec fallback.

Logs
- C:\Temp\vpnaccess-install.log
- C:\Temp\apply-assigned-access.log

Requirements
- Windows 11
- FortiClient already installed machine-wide
- Administrator rights
