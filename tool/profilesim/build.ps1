# Builds build\supervisor.apk, a test-only profile owner for emulator profile users (see profiles.ps1), without Gradle:
# aapt2 + javac + d8 + apksigner from the Android SDK, signed with the debug key.
$ErrorActionPreference = 'Stop'
$here = $PSScriptRoot
$sdk = if ($env:ANDROID_HOME) { $env:ANDROID_HOME } else { "$env:LOCALAPPDATA\Android\Sdk" }
$bt = Get-ChildItem "$sdk\build-tools" | Sort-Object { [version]$_.Name } -ErrorAction SilentlyContinue | Select-Object -Last 1
$bt = $bt.FullName
$jar = (Get-ChildItem "$sdk\platforms\android-3*\android.jar" | Select-Object -Last 1).FullName
if (-not $env:JAVA_HOME) { $env:JAVA_HOME = "C:\Program Files\Android\Android Studio\jbr" }
$jbr = "$env:JAVA_HOME\bin"
$env:PATH = "$jbr;$env:PATH"
$out = "$here\build"
if (Test-Path $out) { Remove-Item -Recurse -Force $out }
New-Item -ItemType Directory -Force "$out\classes", "$out\dex" | Out-Null

& "$bt\aapt2.exe" compile --dir "$here\res" -o "$out\res.zip"
& "$bt\aapt2.exe" link -o "$out\unsigned.apk" -I $jar --manifest "$here\AndroidManifest.xml" "$out\res.zip"
$src = Get-ChildItem -Recurse "$here\src" -Filter *.java | ForEach-Object { $_.FullName }
& "$jbr\javac.exe" --release 11 -cp $jar -d "$out\classes" $src
$classes = Get-ChildItem -Recurse "$out\classes" -Filter *.class | ForEach-Object { $_.FullName }
& "$bt\d8.bat" --lib $jar --min-api 28 --output "$out\dex" $classes
Push-Location "$out\dex"
& "$jbr\jar.exe" uf "$out\unsigned.apk" classes.dex
Pop-Location
& "$bt\zipalign.exe" -f 4 "$out\unsigned.apk" "$out\aligned.apk"
& "$bt\apksigner.bat" sign --ks "$env:USERPROFILE\.android\debug.keystore" --ks-pass pass:android --key-pass pass:android --out "$out\supervisor.apk" "$out\aligned.apk"
Write-Output "built $out\supervisor.apk"
