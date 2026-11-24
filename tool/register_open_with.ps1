param(
  [string]$ExePath = "D:\AI\YDQ\novel_reader\build\windows\x64\runner\Release\novel_reader.exe"
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path -LiteralPath $ExePath)) {
  throw "Executable not found: $ExePath"
}
$ExePath = (Resolve-Path -LiteralPath $ExePath).Path
$AppKey = "HKCU:\Software\Classes\Applications\novel_reader.exe"
$Command = '"' + $ExePath + '" "%1"'
$FriendlyName = [string]::Concat([char]0x4E39, [char]0x9752, [char]0x9605, [char]0x8BFB)

New-Item -Path $AppKey -Force | Out-Null
New-ItemProperty -Path $AppKey -Name "FriendlyAppName" -Value $FriendlyName -PropertyType String -Force | Out-Null
New-Item -Path "$AppKey\shell\open\command" -Force | Out-Null
Set-Item -Path "$AppKey\shell\open\command" -Value $Command
New-Item -Path "$AppKey\DefaultIcon" -Force | Out-Null
Set-Item -Path "$AppKey\DefaultIcon" -Value "$ExePath,0"

New-Item -Path "$AppKey\SupportedTypes" -Force | Out-Null
foreach ($ext in @(".txt", ".md", ".epub", ".mobi", ".azw3", ".azw")) {
  New-ItemProperty -Path "$AppKey\SupportedTypes" -Name $ext -Value "" -PropertyType String -Force | Out-Null
}

# Ask Explorer to refresh the "Open with" list.
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public class ShellNotify {
  [DllImport("shell32.dll")] public static extern void SHChangeNotify(int eventId, int flags, IntPtr item1, IntPtr item2);
}
'@
[ShellNotify]::SHChangeNotify(0x08000000, 0x0000, [IntPtr]::Zero, [IntPtr]::Zero)

Write-Output "registered: $ExePath"
