{ repo, ... }:

# base - every Windows PC of the repo (docs/platforms/windows/renderer.md; its apps are
# packages/winget/base.txt): Microsoft's own privacy switches (Windows AI, activity history,
# peer downloads, typing and speech data, Edge's nags; Edge itself stays),
# LLMNR off, Defender blocking unwanted apps, a few comforts, the prompt and Windows Terminal
# for every console app, and the keyboard (US and Russian, Left Alt+Shift as on Arch). The
# converge's own passes are base too: debloat.ps1 (what must not be there, with --debloat) and
# autostart.ps1 (what may start by itself), and converge.ps1, which applies the build.
{
  windows.role.base = {
    steps = {
      "debloat.ps1" = { source = repo + "/install/windows/dram-windows/debloat.ps1"; phase = "00"; when = "debloat"; };
      "autostart.ps1" = { source = repo + "/install/windows/dram-windows/autostart.ps1"; phase = "40"; };
    };
    files = {
      "converge.ps1".source = repo + "/install/windows/dram-windows/converge.ps1";
      # Arch's own prompt, byte for byte (starship-config points STARSHIP_CONFIG at it)
      "starship.toml".source = repo + "/dotfiles/.config/starship.toml";
    };
    registry = {
      # --- privacy -----------------------------------------------------------------------
      telemetry-required = {
        description = "diagnostic data at required only";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DataCollection'';
        name = "AllowTelemetry"; type = "Dword"; data = "1";
      };
      # The machine's half: Microsoft's own switches, each documented to act on Pro (the
      # Enterprise-only ones are no-ops here and stay out). Nothing is uninstalled for them, no
      # service is touched but the AI fabric's, and Defender keeps its cloud protection and
      # sample submission as shipped.
      activity-history-off = {
        description = "no activity history published (the record Windows keeps of the apps and files used)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System'';
        name = "PublishUserActivities"; type = "Dword"; data = "0";
      };
      activity-history-off-upload = {
        description = "no activity history uploaded to Microsoft";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\System'';
        name = "UploadUserActivities"; type = "Dword"; data = "0";
      };
      delivery-optimization-http-only = {
        description = "updates and Store apps download from Microsoft alone, never from or for other PCs (Delivery Optimization over HTTP only)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\DeliveryOptimization'';
        name = "DODownloadMode"; type = "Dword"; data = "0";
      };
      no-device-metadata = {
        description = "no device companion apps or icons fetched for new hardware (the way MSI's and Lenovo's helpers arrive); drivers still come from Windows Update";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows\Device Metadata'';
        name = "PreventDeviceMetadataFromNetwork"; type = "Dword"; data = "1";
      };
      powershell-telemetry-off = {
        description = "PowerShell 7 sends no telemetry (a machine environment variable, read by each new session)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\Session Manager\Environment'';
        name = "POWERSHELL_TELEMETRY_OPTOUT"; type = "String"; data = "1";
      };
      windows-ai-user = {
        description = "no Click to Do for this user either (the policy's per-user half)";
        key = ''HKEY_CURRENT_USER\Software\Policies\Microsoft\Windows\WindowsAI'';
        name = "DisableClickToDo"; type = "Dword"; data = "1";
      };
      # --- the network and Defender ---
      llmnr-off = {
        description = "no LLMNR name queries broadcast on the network, as Arch's harden.sh (mDNS stays as shipped; LocalSend finds peers by its own multicast)";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows NT\DNSClient'';
        name = "EnableMulticast"; type = "Dword"; data = "0";
      };
      defender-pua-block = {
        description = "Defender blocks potentially unwanted apps (bundlers, adware, miners) by its own policy; Protection history lists what it stopped";
        key = ''HKEY_LOCAL_MACHINE\SOFTWARE\Policies\Microsoft\Windows Defender'';
        name = "PUAProtection"; type = "Dword"; data = "1";
      };
      # --- small comforts: no prompt mid-game, a stop screen that says more ---
      no-sticky-keys-prompt = {
        description = "five Shift presses no longer ask about Sticky Keys (a string, as Windows stores it; from the next sign-in)";
        key = ''HKEY_CURRENT_USER\Control Panel\Accessibility\StickyKeys'';
        name = "Flags"; type = "String"; data = "506";
      };
      bsod-details = {
        description = "a stop screen shows its four parameters beside the stop code (something to search on when PawnIO or the NVIDIA driver fails)";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CrashControl'';
        name = "DisplayParameters"; type = "Dword"; data = "1";
      };
      bsod-details-no-emoticon = {
        description = "a stop screen without the sad face";
        key = ''HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Control\CrashControl'';
        name = "DisableEmoticon"; type = "Dword"; data = "1";
      };
      starship-config = {
        description = "starship reads Arch's starship.toml, staged byte for byte by apply-windows.sh";
        key = ''HKEY_CURRENT_USER\Environment'';
        name = "STARSHIP_CONFIG"; type = "String"; data = ''C:\ProgramData\dram\starship.toml'';
      };
      powershell-5-profile-policy = {
        description = "Windows PowerShell 5.1 runs local profiles (RemoteSigned; PowerShell 7 already does)";
        key = ''HKEY_CURRENT_USER\Software\Microsoft\PowerShell\1\ShellIds\Microsoft.PowerShell'';
        name = "ExecutionPolicy"; type = "String"; data = "RemoteSigned";
      };
      terminal-default-console = {
        description = "Windows Terminal hosts every console app (the console half)";
        key = ''HKEY_CURRENT_USER\Console\%%Startup'';
        name = "DelegationConsole"; type = "String"; data = "{2EACA947-7F5F-4CFA-BA87-8F7FBEEFBE69}";
      };
      terminal-default-terminal = {
        description = "Windows Terminal hosts every console app (the terminal half)";
        key = ''HKEY_CURRENT_USER\Console\%%Startup'';
        name = "DelegationTerminal"; type = "String"; data = "{E12CFF52-A866-4C77-9A90-F570A7AA2C6B}";
      };
      keyboard-toggle = {
        description = "Left Alt+Shift switches the input language (Win+Space does too)";
        key = ''HKEY_CURRENT_USER\Keyboard Layout\Toggle'';
        name = "Language Hotkey"; type = "String"; data = "1";
      };
      keyboard-toggle-legacy = {
        description = "Left Alt+Shift (the older value of the same switch)";
        key = ''HKEY_CURRENT_USER\Keyboard Layout\Toggle'';
        name = "Hotkey"; type = "String"; data = "1";
      };
      keyboard-toggle-layout = {
        description = "no hotkey between layouts of one language";
        key = ''HKEY_CURRENT_USER\Keyboard Layout\Toggle'';
        name = "Layout Hotkey"; type = "String"; data = "3";
      };
    };
    script = {
      privacy-user = {
        description = "no advertising ID, tailored experiences, web search, suggestions or silently installed apps; no online speech recognition, inking and typing data, typing insights, feedback prompts or app-launch tracking";
        elevated = false;
      };
      # --- Windows AI: off through Microsoft's policies, never by removing its packages (Click to
      # Do lives in the CoreAI package, and removing that has left Explorer on its old ribbon) ---
      windows-ai-off = {
        description = "Recall removed (at the next restart) and no snapshots, no Click to Do, no AI in Notepad or Paint";
        elevated = true;
      };
      windows-ai-fabric-manual = {
        description = "the Windows AI Fabric service starts only when something asks for it (Manual), on builds that have it";
        elevated = true;
      };
      # --- Edge stays: only its preload, nags and
      # data sharing go;
      # SmartScreen, certificates and sign-in are left as shipped ---
      edge-policies = {
        description = "Edge is not preloaded or left running, asks nothing at first run, shows no rewards, shopping, sidebar, widgets or suggestions, shares no browsing data and blocks the Copilot extension; Edge Update makes no desktop shortcut";
        elevated = true;
      };
      # --- the keyboard: US and Russian, Left Alt+Shift as on Arch ---------------------------
      # (this user only: copied to the sign-in screen, a stray Alt+Shift would turn a typed
      # password into Cyrillic; the International cmdlets run in Windows PowerShell 5.1)
      keyboard-us-ru = {
        description = "English (US) first, so Windows stays in English, then Russian; no language pack";
        elevated = false;
      };
    };
  };
}
