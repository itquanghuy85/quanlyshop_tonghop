# Build Production APK/AAB Script
# ================================
# Run: .\scripts\build_release.ps1

Write-Host "🚀 Building Production Release..." -ForegroundColor Cyan
Write-Host ""

# Clean previous builds
Write-Host "🧹 Cleaning previous builds..." -ForegroundColor Yellow
flutter clean

# Get dependencies
Write-Host "📦 Getting dependencies..." -ForegroundColor Yellow
flutter pub get

# Build App Bundle (for Google Play)
Write-Host "📱 Building App Bundle (AAB)..." -ForegroundColor Green
flutter build appbundle --release --obfuscate --split-debug-info=build/debug-info

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ App Bundle built successfully!" -ForegroundColor Green
    Write-Host "   Location: build\app\outputs\bundle\release\app-release.aab" -ForegroundColor White
    Write-Host ""
    
    # Get file size
    $aabFile = "build\app\outputs\bundle\release\app-release.aab"
    if (Test-Path $aabFile) {
        $size = (Get-Item $aabFile).Length / 1MB
        Write-Host "   Size: $([math]::Round($size, 2)) MB" -ForegroundColor Cyan
    }
} else {
    Write-Host "❌ Build failed!" -ForegroundColor Red
    exit 1
}

# Optional: Build APK for direct distribution
Write-Host ""
Write-Host "📱 Building APK for direct distribution..." -ForegroundColor Green
flutter build apk --release --obfuscate --split-debug-info=build/debug-info --split-per-abi

if ($LASTEXITCODE -eq 0) {
    Write-Host ""
    Write-Host "✅ APKs built successfully!" -ForegroundColor Green
    Write-Host "   Location: build\app\outputs\flutter-apk\" -ForegroundColor White
    
    # List APK files
    $apkDir = "build\app\outputs\flutter-apk"
    if (Test-Path $apkDir) {
        Get-ChildItem $apkDir -Filter "*.apk" | ForEach-Object {
            $size = $_.Length / 1MB
            Write-Host "   - $($_.Name): $([math]::Round($size, 2)) MB" -ForegroundColor Cyan
        }
    }
}

Write-Host ""
Write-Host "🎉 Production build completed!" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Test the APK on a real device" -ForegroundColor White
Write-Host "2. Upload AAB to Google Play Console" -ForegroundColor White
Write-Host "3. Keep build/debug-info folder for crash symbolication" -ForegroundColor White
