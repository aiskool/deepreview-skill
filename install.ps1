#!/usr/bin/env pwsh
# install.ps1 — install deepreview and deepaudit skills (Windows port).
#
# Usage:
#   irm https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.ps1 | iex
#
# Or, recommended (review before running):
#   irm https://raw.githubusercontent.com/aiskool/deepreview-skill/main/install.ps1 `
#     -OutFile install.ps1
#   notepad install.ps1
#   .\install.ps1
#
# If your execution policy blocks the script, use:
#   powershell -ExecutionPolicy Bypass -File install.ps1
#
# Environment variables (identical to the Bash installer):
#   DEEPREVIEW_SCOPE   "project" (default) or "global"
#   DEEPREVIEW_REF     git ref to install from. Default: "main".
#                      Pin to a tag for reproducibility: $env:DEEPREVIEW_REF="v0.2.1"
#   DEEPREVIEW_REPO    full repo slug, default "aiskool/deepreview-skill"
#   DEEPREVIEW_SKILLS  comma-separated subset to install. Default: "deepreview,deepaudit".
#                      Examples: $env:DEEPREVIEW_SKILLS="deepreview"
#
# IMPORTANT: This installer downloads files. To actually RUN the skills,
# you need Bash available on PATH (via WSL, Git for Windows, Cygwin, or
# MSYS2), because the runtime detector and the SKILL.md examples use Bash.

# --- Strict-ish mode (matches `set -e` semantics; we keep `-u` lenient
# because the env-var fallback pattern uses absent variables on purpose)
$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"   # speeds up Invoke-WebRequest on PS 5.1

# --- Force TLS 1.2 on older PowerShell where it isn't the default
try {
    [Net.ServicePointManager]::SecurityProtocol = `
        [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
} catch {
    # Newer PS already has TLS 1.2+; ignore failure.
}

# --- Helpers ---------------------------------------------------------------

function Get-EnvOrDefault {
    param([string]$Name, [string]$Default)
    $value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrEmpty($value)) { return $Default }
    return $value
}

function Fail {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

# --- Read configuration ---------------------------------------------------

$Scope    = Get-EnvOrDefault "DEEPREVIEW_SCOPE"  "project"
$Ref      = Get-EnvOrDefault "DEEPREVIEW_REF"    "main"
$Repo     = Get-EnvOrDefault "DEEPREVIEW_REPO"   "aiskool/deepreview-skill"
$SkillCsv = Get-EnvOrDefault "DEEPREVIEW_SKILLS" "deepreview,deepaudit"

$Raw = "https://raw.githubusercontent.com/$Repo/$Ref"

# --- Resolve install root -------------------------------------------------

switch ($Scope) {
    "project" {
        if (-not (Test-Path -LiteralPath ".git" -PathType Container)) {
            Fail @"
project scope requires a git repository in the current directory.
       run 'git init' first, or set `$env:DEEPREVIEW_SCOPE='global'.
"@
        }
        $Root = ".claude"
    }
    "global" {
        $Root = Join-Path $HOME ".claude"
    }
    default {
        Fail "DEEPREVIEW_SCOPE must be 'project' or 'global'."
    }
}

# --- Parse and validate skills list ---------------------------------------

$Skills = @($SkillCsv.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$ValidSkills = @("deepreview", "deepaudit")
foreach ($s in $Skills) {
    if ($ValidSkills -notcontains $s) {
        Fail "unknown skill '$s'. Valid: deepreview, deepaudit."
    }
}

# --- Banner ---------------------------------------------------------------

Write-Host "Installing"
Write-Host ("  skills: " + ($Skills -join " "))
Write-Host "  scope:  $Scope"
Write-Host "  ref:    $Ref"
Write-Host "  repo:   $Repo"
Write-Host "  target: $Root/"
Write-Host ""

# --- Create base directories ---------------------------------------------

New-Item -ItemType Directory -Force -Path (Join-Path $Root "agents") | Out-Null

# --- Fetch helper --------------------------------------------------------

function Fetch {
    param([string]$Src, [string]$Dst)
    Write-Host "  fetch  $Src"
    $url = "$Raw/$Src"
    # Ensure parent dir exists
    $parent = Split-Path -Path $Dst -Parent
    if ($parent -and -not (Test-Path -LiteralPath $parent)) {
        New-Item -ItemType Directory -Force -Path $parent | Out-Null
    }
    try {
        Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $Dst
    } catch {
        Fail "failed to fetch $url`n  $($_.Exception.Message)"
    }
}

# --- Per-skill files ------------------------------------------------------

foreach ($skill in $Skills) {
    $skillDir = Join-Path $Root (Join-Path "skills" $skill)
    New-Item -ItemType Directory -Force -Path $skillDir | Out-Null

    Fetch ".claude/skills/$skill/SKILL.md"          (Join-Path $skillDir "SKILL.md")
    Fetch ".claude/skills/$skill/detect-runtime.sh" (Join-Path $skillDir "detect-runtime.sh")
    # No chmod equivalent on Windows; the file ACLs are inherited from the
    # parent and execution depends on Bash interpreter (WSL/Git Bash/etc.).
}

# --- Reviewer agents (deepreview only) -----------------------------------

if ($Skills -contains "deepreview") {
    $reviewerAgents = @(
        "reviewer-security", "reviewer-architecture", "reviewer-bug-hunter",
        "reviewer-performance", "reviewer-test-coverage",
        "reviewer-documentation", "verifier"
    )
    foreach ($agent in $reviewerAgents) {
        Fetch ".claude/agents/$agent.md" (Join-Path $Root (Join-Path "agents" "$agent.md"))
    }
}

# --- Auditor agents (deepaudit only) -------------------------------------

if ($Skills -contains "deepaudit") {
    $auditorAgents = @(
        "auditor-security", "auditor-architecture", "auditor-bug-hunter",
        "auditor-performance", "auditor-test-coverage",
        "auditor-documentation", "auditor-verifier"
    )
    foreach ($agent in $auditorAgents) {
        Fetch ".claude/agents/$agent.md" (Join-Path $Root (Join-Path "agents" "$agent.md"))
    }
}

# --- Summary --------------------------------------------------------------

Write-Host ""
Write-Host ("Installed: " + ($Skills -join " "))
Write-Host "Restart your Claude Code session so the new agents are loaded."
Write-Host ""
if ($Skills -contains "deepreview") {
    Write-Host "  deepreview                    - pre-merge review of a diff"
}
if ($Skills -contains "deepaudit") {
    Write-Host "  deepaudit <scope>             - audit existing code (needs a scope)"
}

Write-Host ""
Write-Host "Note: the skills shell out to bash to detect your project's runtime"
Write-Host "(npm, pytest, cargo, etc.). On Windows, ensure bash is on PATH via:"
Write-Host "  - WSL (recommended)"
Write-Host "  - Git for Windows (Git Bash adds bash to PATH if you tick the option)"
Write-Host "  - Cygwin or MSYS2"
Write-Host "Without bash, the skills will run in static-only mode for executable axes."
