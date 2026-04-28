$f = "c:\FlutterProjects\quanlyshop\lib\views\shop_settings_view.dart"
$all = [System.IO.File]::ReadAllText($f, [System.Text.Encoding]::UTF8)

# Find the corrupt block - use a unique substring to locate it
$corruptStart = "        if (urls.isNotEmpty) {`r`n          logoUrl = urls.first;`r`n              if (_selectedLogo != null) {"
$corruptStartLF = "        if (urls.isNotEmpty) {`n          logoUrl = urls.first;`n              if (_selectedLogo != null) {"

$cleanBlock = "        if (urls.isNotEmpty) {
          logoUrl = urls.first;
        } else {
          final denied = StorageService.lastUploadPermissionDenied ||
              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('unauthorized') ||
              (StorageService.lastUploadErrorMessage ?? '').toLowerCase().contains('permission');
          if (mounted) {
            NotificationService.showSnackBar(
              denied
                  ? 'Khong co quyen tai logo len (loi 403). Kiem tra cau hinh App Check/Storage Firebase.'
                  : 'Tai logo that bai. Vui long kiem tra ket noi mang va thu lai.',
              color: Colors.red,
              duration: const Duration(seconds: 6),
            );
          }
        }
      }"

# Find the end marker: the next "// Update shop data" comment
$endMarker = "      // Update shop data"

$startIdx = $all.IndexOf($corruptStart)
if ($startIdx -lt 0) {
    $startIdx = $all.IndexOf($corruptStartLF)
    Write-Host "Using LF version, startIdx=$startIdx"
} else {
    Write-Host "Using CRLF version, startIdx=$startIdx"
}

if ($startIdx -lt 0) {
    Write-Host "ERROR: Could not find corrupt block start"
    exit 1
}

$endIdx = $all.IndexOf($endMarker, $startIdx)
if ($endIdx -lt 0) {
    Write-Host "ERROR: Could not find end marker"
    exit 1
}

Write-Host "Found block from $startIdx to $endIdx"

# Extract the corrupt block
$corruptBlock = $all.Substring($startIdx, $endIdx - $startIdx)
Write-Host "Corrupt block length: $($corruptBlock.Length)"

# Replace
$fixed = $all.Replace($corruptBlock, $cleanBlock + "`n`n")
[System.IO.File]::WriteAllText($f, $fixed, [System.Text.Encoding]::UTF8)
Write-Host "DONE - file written"
