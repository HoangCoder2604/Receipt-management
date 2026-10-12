$ErrorActionPreference = 'Stop'
Set-Location $PSScriptRoot
function Invoke-Checked([string] $command, [string[]] $arguments) {
    & $command @arguments
    if ($LASTEXITCODE -ne 0) { throw "$command failed with exit code $LASTEXITCODE" }
}
Write-Host 'Creating/updating Android scaffolding...' -ForegroundColor Cyan
Invoke-Checked flutter @('create','--platforms=android','--org','com.vku','--project-name','receiptly','.')
$gradle = 'android/app/build.gradle.kts'
if (Test-Path $gradle) {
    $content = Get-Content $gradle -Raw
    $content = $content.Replace('minSdk = flutter.minSdkVersion', 'minSdk = 23')
    $content = $content.Replace('minSdk = 21', 'minSdk = 23')
    [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $gradle),$content)
} else {
    $gradle = 'android/app/build.gradle'
    if (Test-Path $gradle) {
        $content = Get-Content $gradle -Raw
        $content = $content.Replace('minSdkVersion flutter.minSdkVersion','minSdkVersion 23')
        [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $gradle),$content)
    }
}
$manifest='android/app/src/main/AndroidManifest.xml'
if(Test-Path $manifest) {
  $content=Get-Content $manifest -Raw
  $content=$content.Replace('android:label="receiptly"','android:label="Receiptly"')
  [System.IO.File]::WriteAllText((Join-Path $PSScriptRoot $manifest),$content)
}
Write-Host 'Installing Flutter packages...' -ForegroundColor Cyan
Invoke-Checked flutter @('pub','get')
Write-Host 'Building universal release APK...' -ForegroundColor Cyan
Invoke-Checked flutter @('build','apk','--release')
New-Item -ItemType Directory -Path 'dist' -Force | Out-Null
Copy-Item 'build/app/outputs/flutter-apk/app-release.apk' 'dist/Receiptly-v1.0.0.apk' -Force
Write-Host 'DONE: dist/Receiptly-v1.0.0.apk' -ForegroundColor Green
