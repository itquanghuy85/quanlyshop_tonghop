$max=12
$i=0
$building=$false
while ($i -lt $max) {
  $i = $i + 1
  Write-Host "Kiểm tra lần $i..."
  $out = firebase firestore:indexes --project huyaka-1809 2>&1
  if ($out -match 'BUILDING') {
    Write-Host 'Có index BUILDING'
    $building = $true
    Start-Sleep -Seconds 30
  } else {
    Write-Host 'Không tìm thấy index BUILDING'
    $building = $false
    Write-Output $out
    break
  }
}
if ($building) {
  Write-Host 'Đã hết lượt kiểm tra mà vẫn có index BUILDING. Dừng lại và báo cáo.'
} else {
  Write-Host 'Tất cả index READY hoặc không có BUILDING. Bắt đầu chạy flutter.'
  flutter run -d HATCT4GA89GEBI9P
}
