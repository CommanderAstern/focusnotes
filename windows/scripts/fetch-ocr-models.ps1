$ErrorActionPreference = 'Stop'

$scriptDirectory = Split-Path -Parent $MyInvocation.MyCommand.Path
$windowsDirectory = Split-Path -Parent $scriptDirectory
$manifestPath = Join-Path $windowsDirectory 'src/CaptureApp.Platform/Ocr/ocr-models.json'
$cacheDirectory = Join-Path $windowsDirectory '.ocr-models'
New-Item -ItemType Directory -Force -Path $cacheDirectory | Out-Null
$models = Get-Content -Raw -Path $manifestPath | ConvertFrom-Json

function Get-Sha256([string] $Path) {
    return (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash.ToLowerInvariant()
}

function Ensure-Asset([string] $Path, [string] $Url, [string] $ExpectedSha, [Nullable[long]] $ExpectedBytes) {
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        $existingHash = Get-Sha256 $Path
        $existingBytes = (Get-Item -LiteralPath $Path).Length
        if ($existingHash -eq $ExpectedSha -and (!$ExpectedBytes.HasValue -or $existingBytes -eq $ExpectedBytes.Value)) {
            return
        }
        Remove-Item -LiteralPath $Path -Force
    }

    $temporaryPath = "$Path.partial"
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    Write-Host "Downloading $(Split-Path -Leaf $Path)"
    Invoke-WebRequest -Uri $Url -OutFile $temporaryPath -MaximumRedirection 10
    $actualHash = Get-Sha256 $temporaryPath
    $actualBytes = (Get-Item -LiteralPath $temporaryPath).Length
    if ($actualHash -ne $ExpectedSha) {
        Remove-Item -LiteralPath $temporaryPath -Force
        throw "SHA-256 mismatch for $(Split-Path -Leaf $Path): $actualHash"
    }
    if ($ExpectedBytes.HasValue -and $actualBytes -ne $ExpectedBytes.Value) {
        Remove-Item -LiteralPath $temporaryPath -Force
        throw "Byte count mismatch for $(Split-Path -Leaf $Path): $actualBytes (expected $($ExpectedBytes.Value))"
    }
    Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
}

foreach ($model in $models) {
    Ensure-Asset (Join-Path $cacheDirectory "$($model.id).onnx") $model.url $model.sha256 ([long]$model.bytes)
    if ($model.dictUrl) {
        Ensure-Asset (Join-Path $cacheDirectory "$($model.id).dict.txt") $model.dictUrl $model.dictSha256 $null
    }
}

Write-Host "All OCR model assets are present and verified in $cacheDirectory"
