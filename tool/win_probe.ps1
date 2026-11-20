# Screenshot only the Penna window, optionally click (or scroll) at a point inside it first.
#   pwsh tool/win_probe.ps1 -shot a.png                 # screenshot
#   pwsh tool/win_probe.ps1 -x 38 -y 1082 -shot b.png   # click at window coords, then screenshot
#   pwsh tool/win_probe.ps1 -x 600 -y 500 -wheel        # scroll down there
# Coordinates are physical pixels from the window's top-left corner (same as the screenshot).
# The first click after bringing the window to front may only focus it; click again if nothing happened.
param([int]$procId = 0, [string]$shot, [int]$x = -1, [int]$y = -1, [switch]$wheel)
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class PennaWin {
  [StructLayout(LayoutKind.Sequential)] public struct R { public int L, T, Rt, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out R r);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(int f, int x, int y, int d, int e);
  [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
}
"@
[PennaWin]::SetProcessDPIAware() | Out-Null
$p = if ($procId) { Get-Process -Id $procId } else { Get-Process penna | Where-Object MainWindowHandle -ne 0 | Select-Object -First 1 }
if (-not $p) { throw 'Penna is not running' }
$h = $p.MainWindowHandle
[PennaWin]::SetForegroundWindow($h) | Out-Null
$r = New-Object PennaWin+R; [PennaWin]::GetWindowRect($h, [ref]$r) | Out-Null
if ($x -ge 0) {
  [PennaWin]::SetCursorPos($r.L + $x, $r.T + $y) | Out-Null
  Start-Sleep -Milliseconds 100
  if ($wheel) { [PennaWin]::mouse_event(0x0800, 0, 0, -600, 0) }
  else { [PennaWin]::mouse_event(2, 0, 0, 0, 0); [PennaWin]::mouse_event(4, 0, 0, 0, 0) }
  Start-Sleep -Milliseconds 900
}
if ($shot) {
  $bmp = New-Object Drawing.Bitmap ($r.Rt - $r.L), ($r.B - $r.T)
  $g = [Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($r.L, $r.T, 0, 0, $bmp.Size)
  $bmp.Save([IO.Path]::GetFullPath($shot)); "$($bmp.Width) x $($bmp.Height)"
}
