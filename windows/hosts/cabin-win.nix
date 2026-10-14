{ repo, ... }:

# cabin-win - Windows 11 Pro on cabin's Crucial MX500 1 TB, beside Arch on the same PC
# (docs/platforms/windows/README.md). Rendered by bin/render-windows.sh into
# windows/build/cabin-win/; bin/push-windows.sh cabin-win puts it on the PC for dram.ps1, or
# install/windows/apply-windows.sh converges it directly (docs/platforms/windows/renderer.md).
#   Disks: the MX500 alone; Arch's and the bench's disks are Arch's (Windows boots from its own
#          ESP on the MX500, by its firmware entry; rEFInd stays first)
#   Reach: Windows' OpenSSH at the address below, HostKeyAlias cabin-win, key-only
#
# base is implicit; host-cabin-win (packages/winget/host-cabin-win.txt and the settings below)
# comes with the host. Its own settings are the ones beside Arch (decisions/log.md#d52): the
# clock, Fast Startup and hibernation, power like hypridle, Windows Update's version and
# restarts, DNS as Arch resolves, Secure Boot and the firmware left to Arch, no WCH serial
# driver (decisions/log.md#d142), and the case's temperature panel. The work profile is office
# and college's GUI half with PuTTY and Rufus, the baseline toolchain of every work role; their
# CLI half is the WSL clone's or Arch's.
{
  windows = {
    host = "cabin-win";
    roles = [ "desktop" "chat" "gaming" "creator" "office" "college" "dev" "sysadmin" ];   # one line, as on Arch (decisions/log.md#d52)
    address = "cabin";   # Arch's name too: HostKeyAlias tells the two apart
    user = "pj";
    # listed by its roles, not installed here yet (remove a line to install it)
    hold = [
      "winget:Proton.ProtonPass.CLI"
      "winget:Yubico.YubiKeyManagerCLI"
      "winget:SumatraPDF.SumatraPDF"
      "winget:Qalculate.Qalculate"
    ];
    # installed by hand and kept out of the build (decisions/log.md#d144): dram harvest skips them
    unmanaged = [ "winget:Blitz.Blitz" ];
  };

  windows.role.host-cabin-win = {
    files = {
      # run by the SYSTEM tasks below, not by the converge
      "boot-guard.ps1".source = repo + "/install/windows/dram-windows/boot-guard.ps1";
      "case-display.ps1".source = repo + "/install/windows/dram-windows/case-display.ps1";
    };
    registry = {
      # --- beside Arch ----------------------------------------------------------------
      utc-clock = {
        description = "the hardware clock is read as UTC (Arch keeps it so)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\TimeZoneInformation'';
        name = "RealTimeIsUniversal"; type = "Dword"; data = "1";
      };
      no-fast-startup = {
        description = "Fast Startup off (Arch mounts this disk cleanly)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Power'';
        name = "HiberbootEnabled"; type = "Dword"; data = "0";
      };
      no-auto-device-encryption = {
        description = "no automatic device encryption (BitLocker is turned on by hand)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\BitLocker'';
        name = "PreventDeviceEncryption"; type = "Dword"; data = "1";
      };
      no-firmware-installers = {
        description = "Windows runs nothing a firmware table hands it (MSI's bundle comes that way)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager'';
        name = "DisableWpbtExecution"; type = "Dword"; data = "1";
      };
      # Windows Update beside Arch: this value, and the three Script units under script
      windows-update-drivers = {
        description = "drivers keep coming with Windows Update (the NVIDIA driver): the policy that would exclude them, declared off";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'';
        name = "ExcludeWUDriversInQualityUpdate"; type = "Dword"; data = "0";
      };
      # --- Arch owns the boot chain (docs/platforms/windows/boot-guard.md): Windows changes no
      # Secure Boot variable, firmware or boot order of its own accord ---
      secureboot-no-managed-rollout = {
        description = "no Microsoft-managed Secure Boot variable rollout (Arch owns KEK, db and dbx)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Secureboot'';
        name = "HighConfidenceOptOut"; type = "Dword"; data = "1";
      };
      no-firmware-class-installs = {
        description = "no UEFI capsule (firmware) packages from Windows Update: the BIOS comes from M-Flash";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'';
        name = "DenyDeviceClasses"; type = "Dword"; data = "1";
      };
      no-firmware-class-installs-list = {
        description = "the Firmware setup class (the NVIDIA driver is Display class: unaffected)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceClasses'';
        name = "1"; type = "String"; data = "{f2e7dd72-6468-4e36-b6f1-6488f42c1b52}";
      };
      # WCH's USB-serial chips (vendor 1A86; Nanjing Qinheng): Windows Update would install WCH's
      # own driver the moment a board is plugged in (decisions/log.md#d142; no software from China,
      # decisions/0013). cabin
      # only: thermos's re-lab hands a CH341A to its WSL clone through usbipd, which a device-ID
      # ban could stop too; on Arch the kernel's own ch341 driver serves them. A new WCH product
      # id goes in this list.
      no-wch-driver-installs = {
        description = "no driver install for WCH's USB-serial chips (their only driver is WCH's own)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions'';
        name = "DenyDeviceIDs"; type = "Dword"; data = "1";
      };
      no-wch-driver-installs-1 = {
        description = "WCH CH340 (USB 1A86:7523)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "1"; type = "String"; data = ''USB\VID_1A86&PID_7523'';
      };
      no-wch-driver-installs-2 = {
        description = "WCH CH340K (USB 1A86:7522)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "2"; type = "String"; data = ''USB\VID_1A86&PID_7522'';
      };
      no-wch-driver-installs-3 = {
        description = "WCH CH341 serial (USB 1A86:5523)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "3"; type = "String"; data = ''USB\VID_1A86&PID_5523'';
      };
      no-wch-driver-installs-4 = {
        description = "WCH CH341A as a programmer (USB 1A86:5512)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "4"; type = "String"; data = ''USB\VID_1A86&PID_5512'';
      };
      no-wch-driver-installs-5 = {
        description = "WCH CH342 (USB 1A86:55D2)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "5"; type = "String"; data = ''USB\VID_1A86&PID_55D2'';
      };
      no-wch-driver-installs-6 = {
        description = "WCH CH343 (USB 1A86:55D3)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "6"; type = "String"; data = ''USB\VID_1A86&PID_55D3'';
      };
      no-wch-driver-installs-7 = {
        description = "WCH CH9102 (USB 1A86:55D4)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeviceInstall\Restrictions\DenyDeviceIDs'';
        name = "7"; type = "String"; data = ''USB\VID_1A86&PID_55D4'';
      };
    };
    script = {
      time-zone-and-hibernation = {
        description = "US Eastern time like Arch (America/New_York), hibernation off";
        elevated = true;
      };
      power-like-arch = {
        description = "as Arch's hypridle on this desktop: never sleeps on AC, locks at 30 min, screens off at 45";
        elevated = true;
      };
      # --- Windows Update beside Arch (2026-10-12): the feature version stays until the repo
      # moves it, as Arch moves by release (each move tested with League); monthly security and
      # Secure Boot servicing keep coming; a restart waits for pj, and one Windows makes with
      # nobody signed in boots rEFInd's default, Arch, so the update finishes at the next Windows
      # start. Drivers keep coming from Windows Update (the NVIDIA driver); firmware does not
      # (the Firmware class stays denied, below). Never WinUtil's update modes or its reset: the
      # reset deletes every policy here, the firmware block included ---
      windows-update-feature-pin = {
        description = "Windows 11 stays on 26H2, the version cabin runs, until this line moves";
        elevated = true;
      };
      windows-update-active-hours = {
        description = "active hours 08:00 to 02:00 (18 hours, the most Windows allows): no update restart inside them";
        elevated = true;
      };
      windows-update-no-restart-signed-in = {
        description = "updates download and install by themselves, but Windows never restarts for them while pj is signed in (option 4, the one that restart rule needs)";
        elevated = true;
      };
      # --- DNS beside Arch: Quad9 over Windows' own DNS-over-HTTPS (Arch: Quad9 over DoT), on the
      # Ethernet adapter only - a WireGuard or OpenVPN tunnel keeps the DNS its config names.
      # Plaintext fallback allowed, as Arch's DoT is opportunistic (2026-10-12). The four
      # addresses are on Windows' built-in DoH list (Get-DnsClientDohServerAddress); the router's
      # DNS is no longer asked, so LAN-only names do not resolve here, as on Arch ---
      dns-quad9-doh = {
        description = "Quad9 (9.9.9.9, 149.112.112.112 and IPv6) over DNS-over-HTTPS on the Ethernet adapter, plaintext fallback allowed";
        elevated = true;
      };
      secureboot-no-revocations = {
        description = "Windows never queues the PCA 2011 revocation (0x80), SVN (0x200) or SBAT (0x400) updates; Arch decides those";
        elevated = true;
      };
      boot-guard-task = {
        description = "rEFInd first and Windows Boot Manager last in the firmware order at every Windows start (dram-windows/boot-guard.ps1)";
        elevated = true;
      };
      # --- the case's temperature panel (Antec Flux Pro, USB 2022:0522; pkgs/dram-case-display/README.md):
      # PawnIO from host-cabin-win.txt, LibreHardwareMonitor's library, then the task (phase 40,
      # once both are in) ---
      case-display-lhm = {
        description = "LibreHardwareMonitor 0.9.6's library for the panel (MPL-2.0; the release zip, pinned by SHA-256)";
        elevated = true;
        phase = "30";
        package = "manual:librehardwaremonitor-lib";
      };
      case-display-task = {
        description = "the SYSTEM task dram-case-display: case-display.ps1 from startup, restarted if it stops";
        elevated = true;
        phase = "40";
      };
    };
  };
}
