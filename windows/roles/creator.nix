{ ... }:

# creator - OBS (packages/winget/creator.txt) with its own virtual camera and FOSS background
# removal, which replaced XSplit VCam (2026-10-12, decisions/log.md#d93); Vesktop picks "OBS
# Virtual Camera".
{
  windows.role.creator = {
    script = {
      obs-background-removal = {
        description = "OBS background removal 1.4.1 (GPL-3.0, pinned by SHA-256): with OBS's own virtual camera it replaces XSplit VCam (2026-10-12)";
        elevated = true;
        phase = "30";
        package = "manual:obs-backgroundremoval";
      };
    };
  };
}
