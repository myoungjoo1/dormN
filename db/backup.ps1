param(
    [string]$OutputDirectory = (Join-Path $PSScriptRoot "backups")
)

$ErrorActionPreference = "Stop"

$databaseUrl = $env:DORMN_DATABASE_URL
if ([string]::IsNullOrWhiteSpace($databaseUrl)) {
    throw "Set DORMN_DATABASE_URL in this PowerShell session before running the backup."
}

$pgDumpCommand = Get-Command pg_dump -ErrorAction SilentlyContinue
$pgDumpPath = if ($null -ne $pgDumpCommand) {
    $pgDumpCommand.Source
} else {
    @(
        (Join-Path $env:LOCALAPPDATA "Programs\pgAdmin 4\runtime\pg_dump.exe"),
        (Join-Path $env:ProgramFiles "pgAdmin 4\runtime\pg_dump.exe"),
        (Join-Path ${env:ProgramFiles(x86)} "pgAdmin 4\runtime\pg_dump.exe")
    ) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
}

if ([string]::IsNullOrWhiteSpace($pgDumpPath)) {
    throw "pg_dump was not found in PATH. Install PostgreSQL client tools first."
}

New-Item -ItemType Directory -Force -Path $OutputDirectory | Out-Null
$resolvedOutputDirectory = (Resolve-Path -LiteralPath $OutputDirectory).Path
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
$backupPath = Join-Path $resolvedOutputDirectory "dormn-$timestamp.dump"

& $pgDumpPath `
    "--dbname=$databaseUrl" `
    "--format=custom" `
    "--no-owner" `
    "--no-privileges" `
    "--file=$backupPath"

if ($LASTEXITCODE -ne 0) {
    throw "pg_dump failed with exit code $LASTEXITCODE."
}

Write-Output "Backup created: $backupPath"
