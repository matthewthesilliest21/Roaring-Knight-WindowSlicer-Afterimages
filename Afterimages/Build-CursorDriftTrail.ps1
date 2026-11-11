param(
    [string]$OutputName = 'CursorDriftTrail.exe'
)

$ErrorActionPreference = 'Stop'

$source = Join-Path $PSScriptRoot 'CursorDriftTrail.cs'
$output = Join-Path $PSScriptRoot $OutputName
$compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $compiler)) {
    $compiler = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'
}

if (-not (Test-Path -LiteralPath $compiler)) {
    throw 'The Windows .NET Framework C# compiler was not found.'
}
if (-not (Test-Path -LiteralPath $source)) {
    throw "Source file not found: $source"
}

$compilerArgs = @(
    '/nologo',
    '/target:winexe',
    '/optimize+',
    '/platform:anycpu',
    "/out:$output",
    '/reference:System.dll',
    '/reference:System.Drawing.dll',
    '/reference:System.Windows.Forms.dll',
    $source
)

& $compiler @compilerArgs
if ($LASTEXITCODE -ne 0) {
    throw "Compilation failed with exit code $LASTEXITCODE."
}

Write-Host "Created $output"
