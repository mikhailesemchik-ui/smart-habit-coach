# Runs the same checks as CI, locally. Windows PowerShell.
#
# Usage (from the repo root):
#   .\scripts\test_all.ps1
#
# Exits non-zero on the first failing step so it's safe to chain in a
# pre-commit habit: `.\scripts\test_all.ps1; if ($?) { git commit ... }`

$ErrorActionPreference = "Stop"

Write-Host "== dart format ==" -ForegroundColor Cyan
dart format --output=none --set-exit-if-changed lib test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter analyze ==" -ForegroundColor Cyan
flutter analyze
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== flutter test ==" -ForegroundColor Cyan
flutter test
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "== git diff --check ==" -ForegroundColor Cyan
git diff --check
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Write-Host "All checks passed." -ForegroundColor Green
