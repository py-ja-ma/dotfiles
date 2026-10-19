{ ... }:

# What a packages/winget line cannot say (decisions/0020): a package's unit id and description,
# a pinned version, the context it installs in, and how a manual: name no unit installs gets
# there. A listed winget: or msstore: name without an entry here still renders - its unit id
# is made from the package id, its description is the id, a winget package installs
# machine-wide (elevated) and a Store app in pj's context - so a name added to a role's list
# needs nothing here to be installed. An entry for a name no list has fails the render.
{
  windows.packages = {
    # --- base ---
    "winget:Microsoft.PowerShell" = { id = "powershell-7"; description = "PowerShell 7"; };
    "winget:Starship.Starship" = { id = "starship"; description = "starship, the prompt Arch uses (ISC)"; };
    "winget:WireGuard.WireGuard" = { id = "wireguard"; description = "WireGuard"; };
    "winget:Proton.ProtonPass" = { id = "proton-pass"; description = "Proton Pass"; };

    # --- chat, as on every build (Mumble, Halloy for IRC; TeamSpeak under a waiver) ---
    "winget:Mumble.Mumble.Client" = { id = "mumble"; description = "Mumble (voice)"; };
    "winget:squidowl.halloy" = { id = "halloy"; description = "Halloy (IRC)"; };
    "winget:TeamSpeakSystems.TeamSpeakClient" = { id = "teamspeak"; description = "TeamSpeak 3 (proprietary, waived)"; };
    "winget:Vencord.Vesktop" = { id = "vesktop"; description = "Vesktop (Discord)"; };

    # --- creator ---
    "winget:OBSProject.OBSStudio" = { id = "obs-studio"; description = "OBS Studio"; };

    # --- desktop ---
    "winget:LibreWolf.LibreWolf" = { id = "librewolf"; description = "LibreWolf"; };
    "winget:Mozilla.Thunderbird" = { id = "thunderbird"; description = "Thunderbird"; };
    "winget:Proton.ProtonMailBridge" = { id = "proton-mail-bridge"; description = "Proton Mail Bridge"; };
    # the Store build: winget's own Spotify installer refuses to run elevated
    "msstore:9NCBCSZSJRSB" = { id = "spotify"; description = "Spotify (Microsoft Store source)"; };
    "winget:LocalSend.LocalSend" = { id = "localsend"; description = "LocalSend"; };
    "winget:Microsoft.PowerToys" = { id = "powertoys"; description = "PowerToys"; };
    "winget:Notepad++.Notepad++" = { id = "notepad-plus-plus"; description = "Notepad++"; };
    "winget:VideoLAN.VLC" = { id = "vlc"; description = "VLC"; };
    "winget:nomacs.nomacs" = { id = "nomacs"; description = "nomacs (image viewer)"; };
    "winget:WinDirStat.WinDirStat" = { id = "windirstat"; description = "WinDirStat (disk usage)"; };
    "winget:Transmission.Transmission" = { id = "transmission"; description = "Transmission (torrents; qBittorrent swapped out 2026-10-12)"; };
    # the masthead: Zebar (GPL-3.0, glzr.io; WebView2 widgets, nothing injected) draws
    # letterpress\zebar (bin/gen-windows-look.py; look.ps1 puts it in %USERPROFILE%\.glzr\zebar)
    # and reserves the top edge; Windows' taskbar auto-hides at the bottom (apply-live.ps1, which
    # also starts the bar on the desktop now). Pinned: masthead.js speaks 3.3.1's IPC, so a bump
    # re-checks it; a later Zebar is put back (its MSI allows downgrades). No GlazeWM, so no
    # workspace numeral: it is held for its IPC (glzr-io/glazewm#1443).
    "winget:glzr-io.zebar" = { id = "zebar"; description = "Zebar 3.3.1, the masthead's bar (a machine-wide MSI)"; version = "3.3.1"; };

    # --- dev ---
    "winget:VSCodium.VSCodium" = { id = "vscodium"; description = "VSCodium"; };

    # --- gaming ---
    "winget:Valve.Steam" = { id = "steam"; description = "Steam"; };
    "winget:EpicGames.EpicGamesLauncher" = { id = "epic-games"; description = "Epic Games Launcher"; };
    "winget:ElectronicArts.EADesktop" = { id = "ea-app"; description = "EA app"; };
    "winget:HypixelStudios.Hytale" = { id = "hytale"; description = "Hytale Launcher"; };
    "winget:RuneLite.RuneLite" = { id = "runelite"; description = "RuneLite"; };
    "winget:NexusMods.Vortex" = { id = "vortex"; description = "Vortex (mod manager)"; };
    "winget:PrismLauncher.PrismLauncher" = { id = "prismlauncher"; description = "Prism Launcher (Minecraft; a per-user installer, as Anki's is)"; };
    "winget:WowUp.Wowup" = { id = "wowup"; description = "WowUp (World of Warcraft add-ons from Wago Addons, WoWInterface, GitHub and tukui.org; a per-user installer)"; };

    # --- office and college: the work and finance profiles' GUI half
    # (docs/platforms/windows/renderer.md), each the project Arch installs (its register row the Arch row's twin); winget
    # picks each installer's scope (Anki's is per user, as Halloy's is); LibreOffice comes from
    # winget's one channel, the newer line, where Arch keeps still ---
    "winget:calibre.calibre" = { id = "calibre"; description = "calibre"; };
    "winget:TheDocumentFoundation.LibreOffice" = { id = "libreoffice"; description = "LibreOffice (documents)"; };
    "winget:Zettlr.Zettlr" = { id = "zettlr"; description = "Zettlr (the Markdown vault; pandoc, for its exports, comes with it)"; };
    "winget:simonmichael.hledger" = { id = "hledger"; description = "hledger, hledger-ui and hledger-web (the finance journal; a portable zip, on PATH)"; };
    "winget:PDFArranger.PDFArranger" = { id = "pdf-arranger"; description = "PDF Arranger (merge, split, rotate and reorder pages)"; };
    "winget:QPDF.QPDF" = { id = "qpdf"; description = "QPDF (a PDF's structure, encryption and repair, on the command line)"; };
    "winget:KiCad.KiCad" = { id = "kicad"; description = "KiCad (schematics and boards, with its libraries; pass-flag: decisions/log.md#d139)"; };
    "winget:GNU.Octave" = { id = "octave"; description = "GNU Octave (MATLAB-compatible maths)"; };
    "winget:Typst.Typst" = { id = "typst"; description = "Typst (reports; a portable binary, on PATH)"; };
    "winget:JGraph.Draw" = { id = "drawio"; description = "draw.io (diagrams)"; };
    "winget:Xournal++.Xournal++" = { id = "xournalpp"; description = "Xournal++ (handwritten notes, PDF annotation)"; };
    "winget:Anki.Anki" = { id = "anki"; description = "Anki (flash cards)"; };
    "winget:ArduinoSA.CLI" = { id = "arduino-cli"; description = "Arduino CLI (microcontrollers; each board's toolchain comes with its core)"; };

    # --- sysadmin: network, serial consoles and boot sticks (npcap and a current nmap need their
    # installers' clicks: neither is installed, decisions/log.md#d110) ---
    "winget:WiresharkFoundation.Wireshark" = { id = "wireshark"; description = "Wireshark"; };
    "winget:OpenVPNTechnologies.OpenVPN" = { id = "openvpn"; description = "OpenVPN (the community client and GUI)"; };
    "winget:PuTTY.PuTTY" = { id = "putty"; description = "PuTTY (serial consoles; ssh itself is Windows' own OpenSSH)"; };
    "winget:Rufus.Rufus" = { id = "rufus"; description = "Rufus (boot sticks; Ventoy fails Origin)"; };

    # --- cabin-win: the case's temperature panel (Antec Flux Pro, USB 2022:0522; pkgs/dram-case-display/README.md) ---
    "winget:namazso.PawnIO" = { id = "pawnio"; description = "PawnIO (the driver that lets LibreHardwareMonitor read the CPU temperature; pass-flag, 2026-10-12)"; };
    "manual:nvidia-app".byHand = "by hand from nvidia.com (not in winget); the driver itself comes from Windows Update (decisions/log.md#d102)";
  };
}
