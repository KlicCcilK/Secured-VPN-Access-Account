VPN break-glass package
=======================

Contents
- install.cmd                 Double-click this after unzipping
- Install-VpnAccess.ps1       Main installer
- Apply-AssignedAccess.ps1    Applies the Assigned Access XML as SYSTEM
- vpn-restricted-accounts.xml Restricted profile for the local group
- PsTools.zip                 YOU MUST ADD THIS before deploying
                              Download from Microsoft Sysinternals PsTools

How to build the zip you send to devices
1. Download PsTools.zip from Microsoft and drop it in this folder.
2. Zip this whole folder.
3. Copy the zip to the target PC.

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
- Creates local group "Restricted User Experience" if missing
- Adds VPNaccess to that group and to Users
- Creates C:\Tools and C:\Temp
- Extracts PsTools.zip to C:\Tools\PsTools
- Adds C:\Tools\PsTools to the system PATH
- Copies the XML and apply script to C:\Temp
- Applies Assigned Access as SYSTEM
- Hides the Outlook (new) taskbar pin
- Does not AppLocker-deny OUTLOOK.EXE or deprovision Office

Logs
- C:\Temp\vpnaccess-install.log
- C:\Temp\apply-assigned-access.log
