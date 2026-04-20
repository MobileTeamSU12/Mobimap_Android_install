param(
    [string]$RepoPath = (Get-Location).Path,
    [string[]]$PathGlobs = @("*.apk"),
    [string]$BackupRoot,
    [switch]$PushCurrentBranch,
    [switch]$SkipPull,
    [switch]$Interactive
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$script:ProgressStep = 0
$script:ProgressTotal = 0
$script:IsInteractiveSession = $false

function Write-Step {
    param([string]$Message)
    Write-Host "==> $Message"
}

function Start-StepProgress {
    param(
        [string]$Activity,
        [int]$TotalSteps
    )

    $script:ProgressStep = 0
    $script:ProgressTotal = $TotalSteps
    Write-Progress -Activity $Activity -Status "Bat dau" -PercentComplete 0
}

function Advance-StepProgress {
    param([string]$Status)

    $script:ProgressStep++
    $percent = if ($script:ProgressTotal -gt 0) {
        [int](($script:ProgressStep / $script:ProgressTotal) * 100)
    } else {
        0
    }

    Write-Host ("[{0}/{1}] {2}" -f $script:ProgressStep, $script:ProgressTotal, $Status)
    Write-Progress -Activity "Toi uu lich su repo" -Status $Status -PercentComplete $percent
}

function Finish-StepProgress {
    Write-Progress -Activity "Toi uu lich su repo" -Completed
}

function Require-Command {
    param([string]$Name)
    if (-not (Get-Command $Name -ErrorAction SilentlyContinue)) {
        throw "Khong tim thay command '$Name'."
    }
}

function Invoke-Git {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments,
        [switch]$AllowFailure
    )

    & git @Arguments
    if (-not $AllowFailure -and $LASTEXITCODE -ne 0) {
        throw "Lenh git that bai: git $($Arguments -join ' ')"
    }
}

function Ensure-GitFilterRepo {
    $candidate = Join-Path $env:APPDATA "Python\Python313\Scripts\git-filter-repo.exe"
    if (Test-Path $candidate) {
        return $candidate
    }

    $command = Get-Command git-filter-repo -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    Require-Command py
    Write-Step "Cai dat git-filter-repo"
    & py -m pip install --user git-filter-repo
    if ($LASTEXITCODE -ne 0) {
        throw "Khong cai duoc git-filter-repo."
    }

    if (-not (Test-Path $candidate)) {
        throw "Da cai git-filter-repo nhung khong tim thay file thuc thi."
    }

    return $candidate
}

function Ensure-LfsTracking {
    param([string[]]$Patterns)

    $gitattributesPath = Join-Path (Get-Location) ".gitattributes"
    $existing = @()
    if (Test-Path $gitattributesPath) {
        $existing = Get-Content $gitattributesPath
    }

    $updated = [System.Collections.Generic.List[string]]::new()
    if ($existing.Count -gt 0) {
        foreach ($line in $existing) {
            $updated.Add($line)
        }
    }

    $changed = $false
    foreach ($pattern in $Patterns) {
        $rule = "$pattern filter=lfs diff=lfs merge=lfs -text"
        if (-not ($existing -contains $rule)) {
            $updated.Add($rule)
            $changed = $true
        }
    }

    if ($changed) {
        Set-Content -Path $gitattributesPath -Value $updated -Encoding utf8
    }
}

function Get-DirectorySizeBytes {
    param([string]$Path)

    if (-not (Test-Path $Path)) {
        return 0L
    }

    $measure = Get-ChildItem -LiteralPath $Path -Force -Recurse -File | Measure-Object -Property Length -Sum
    if ($null -eq $measure.Sum) {
        return 0L
    }

    return [int64]$measure.Sum
}

function Format-Bytes {
    param([int64]$Bytes)

    if ($Bytes -ge 1GB) {
        return "{0:N3} GB" -f ($Bytes / 1GB)
    }

    if ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    }

    if ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    }

    return "$Bytes B"
}

function Show-RepoSizeReport {
    param([string]$Label)

    $repoSize = Get-DirectorySizeBytes -Path (Get-Location).Path
    $gitSize = Get-DirectorySizeBytes -Path (Join-Path (Get-Location) ".git")
    $lfsSize = Get-DirectorySizeBytes -Path (Join-Path (Get-Location) ".git\lfs")

    Write-Host ""
    Write-Host "[$Label]"
    Write-Host ("Repo      : {0}" -f (Format-Bytes $repoSize))
    Write-Host ("Git dir   : {0}" -f (Format-Bytes $gitSize))
    Write-Host ("Git LFS   : {0}" -f (Format-Bytes $lfsSize))
    Write-Host ""
}

function Show-SelectedOptions {
    param(
        [bool]$SkipPullValue,
        [bool]$PushCurrentBranchValue,
        [string[]]$Patterns
    )

    Write-Host ""
    Write-Host "[Cau hinh da chon]"
    Write-Host ("Pattern   : {0}" -f ($Patterns -join ", "))
    Write-Host ("Pull truoc: {0}" -f ($(if ($SkipPullValue) { "Khong" } else { "Co" })))
    Write-Host ("Push force: {0}" -f ($(if ($PushCurrentBranchValue) { "Co" } else { "Khong" })))
    Write-Host ""
}

function Prompt-YesNo {
    param(
        [string]$Question,
        [bool]$DefaultValue
    )

    $suffix = if ($DefaultValue) { "[Y/n]" } else { "[y/N]" }
    $inputValue = (Read-Host "$Question $suffix").Trim()
    if ([string]::IsNullOrWhiteSpace($inputValue)) {
        return $DefaultValue
    }

    return $inputValue -match '^(y|yes)$'
}

function Resolve-InteractiveOptions {
    Write-Host ""
    Write-Host "Chon cach chay script:"
    Write-Host "1. Toi uu lich su, co pull truoc khi chay"
    Write-Host "2. Toi uu lich su, co pull va push force sau khi xong"
    Write-Host "3. Toi uu lich su, bo qua pull"
    Write-Host "4. Toi uu lich su, bo qua pull va push force sau khi xong"
    Write-Host "5. Tuy chinh"
    Write-Host ""

    do {
        $choice = (Read-Host "Nhap so lua chon").Trim()
    } while ($choice -notin @("1", "2", "3", "4", "5"))

    switch ($choice) {
        "1" {
            return @{
                SkipPull = $false
                PushCurrentBranch = $false
                PathGlobs = @("*.apk")
            }
        }
        "2" {
            return @{
                SkipPull = $false
                PushCurrentBranch = $true
                PathGlobs = @("*.apk")
            }
        }
        "3" {
            return @{
                SkipPull = $true
                PushCurrentBranch = $false
                PathGlobs = @("*.apk")
            }
        }
        "4" {
            return @{
                SkipPull = $true
                PushCurrentBranch = $true
                PathGlobs = @("*.apk")
            }
        }
        "5" {
            $patternsInput = (Read-Host "Nhap pattern can don, cach nhau boi dau phay, de trong de dung *.apk").Trim()
            $patterns = if ([string]::IsNullOrWhiteSpace($patternsInput)) {
                @("*.apk")
            } else {
                $patternsInput.Split(",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }
            }

            return @{
                SkipPull = -not (Prompt-YesNo -Question "Pull branch hien tai tu remote truoc khi chay?" -DefaultValue $true)
                PushCurrentBranch = (Prompt-YesNo -Question "Push force branch hien tai sau khi toi uu?" -DefaultValue $false)
                PathGlobs = $patterns
            }
        }
    }
}

function Get-MatchingHeadPaths {
    param([string[]]$Patterns)

    $paths = Invoke-GitCapture @("ls-tree", "-r", "--name-only", "HEAD")
    $matched = foreach ($path in $paths) {
        foreach ($pattern in $Patterns) {
            if ($path -like $pattern) {
                $path
                break
            }
        }
    }

    return $matched | Sort-Object -Unique
}

function Invoke-GitCapture {
    param([string[]]$Arguments)

    $output = & git @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Lenh git that bai: git $($Arguments -join ' ')"
    }
    return $output
}

function Export-GitBlob {
    param(
        [string]$Spec,
        [string]$DestinationPath
    )

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = "git"
    $startInfo.WorkingDirectory = (Get-Location).Path
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.ArgumentList.Add("show")
    $startInfo.ArgumentList.Add($Spec)

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $process.Start() | Out-Null

    $fileStream = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write)
    try {
        $process.StandardOutput.BaseStream.CopyTo($fileStream)
    } finally {
        $fileStream.Dispose()
    }

    $stderr = $process.StandardError.ReadToEnd()
    $process.WaitForExit()
    if ($process.ExitCode -ne 0) {
        throw "Khong doc duoc file tu HEAD: $Spec`n$stderr"
    }
}

function Save-HeadFiles {
    param(
        [string]$SnapshotRoot,
        [string[]]$Paths
    )

    foreach ($relativePath in $Paths) {
        $targetPath = Join-Path $SnapshotRoot $relativePath
        $targetDir = Split-Path $targetPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Export-GitBlob -Spec "HEAD:$relativePath" -DestinationPath $targetPath
    }
}

function Restore-SnapshotFiles {
    param(
        [string]$SnapshotRoot,
        [string[]]$Paths
    )

    foreach ($relativePath in $Paths) {
        $sourcePath = Join-Path $SnapshotRoot $relativePath
        if (-not (Test-Path $sourcePath)) {
            throw "Khong tim thay file snapshot: $relativePath"
        }

        $targetPath = Join-Path (Get-Location) $relativePath
        $targetDir = Split-Path $targetPath -Parent
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $sourcePath -Destination $targetPath -Force
    }
}

Require-Command git
Require-Command git-lfs

try {
    if ($Interactive -or $PSBoundParameters.Count -eq 0) {
        $script:IsInteractiveSession = $true
        $selectedOptions = Resolve-InteractiveOptions
        $SkipPull = [bool]$selectedOptions.SkipPull
        $PushCurrentBranch = [bool]$selectedOptions.PushCurrentBranch
        $PathGlobs = [string[]]$selectedOptions.PathGlobs
    }

    $resolvedRepoPath = (Resolve-Path $RepoPath).Path
    Set-Location $resolvedRepoPath

    $status = Invoke-GitCapture @("status", "--porcelain")
    if ($status.Count -ne 0) {
        throw "Repo dang co thay doi chua commit. Hay commit hoac stash truoc khi chay script."
    }

    $currentBranch = (Invoke-GitCapture @("rev-parse", "--abbrev-ref", "HEAD")).Trim()
    $originUrl = ""
    try {
        $originUrl = (Invoke-GitCapture @("remote", "get-url", "origin")).Trim()
    } catch {
        $originUrl = ""
    }

    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    if (-not $BackupRoot) {
        $repoName = Split-Path $resolvedRepoPath -Leaf
        $BackupRoot = Join-Path (Split-Path $resolvedRepoPath -Parent) "$repoName-history-backup-$timestamp"
    }

    $backupMirrorPath = "$BackupRoot.git"
    $snapshotPath = Join-Path $BackupRoot "head-files"
    $filterRepo = Ensure-GitFilterRepo

    $headPaths = Get-MatchingHeadPaths -Patterns $PathGlobs
    if ($headPaths.Count -eq 0) {
        throw "Khong tim thay file nao trong HEAD khop voi PathGlobs."
    }

    Show-SelectedOptions -SkipPullValue $SkipPull -PushCurrentBranchValue $PushCurrentBranch -Patterns $PathGlobs

    if ($PushCurrentBranch) {
        Start-StepProgress -Activity "Toi uu lich su repo" -TotalSteps 10
    } else {
        Start-StepProgress -Activity "Toi uu lich su repo" -TotalSteps 9
    }

    Advance-StepProgress -Status "Do dung luong repo hien tai"
    Show-RepoSizeReport -Label "Truoc khi toi uu"

    if ($originUrl -and -not $SkipPull) {
        Advance-StepProgress -Status "Pull branch hien tai tu remote"
        Write-Step "Pull branch $currentBranch tu remote bang fast-forward only"
        Invoke-Git -Arguments @("pull", "--ff-only", "origin", $currentBranch)
    } else {
        Advance-StepProgress -Status "Bo qua pull tu remote"
    }

    Advance-StepProgress -Status "Tao mirror backup"
    Write-Step "Tao mirror backup tai $backupMirrorPath"
    & git clone --mirror $resolvedRepoPath $backupMirrorPath
    if ($LASTEXITCODE -ne 0) {
        throw "Khong tao duoc mirror backup."
    }

    Advance-StepProgress -Status "Luu snapshot cac file HEAD"
    Write-Step "Luu lai cac file hien co o HEAD"
    Save-HeadFiles -SnapshotRoot $snapshotPath -Paths $headPaths

    Advance-StepProgress -Status "Dam bao cau hinh Git LFS"
    Write-Step "Dam bao rule Git LFS cho cac pattern"
    Ensure-LfsTracking -Patterns $PathGlobs
    Invoke-Git -Arguments @("add", ".gitattributes")
    Invoke-Git -Arguments @("commit", "-m", "Ensure Git LFS tracking before cleanup") -AllowFailure

    $filterArgs = @("--force")
    foreach ($pattern in $PathGlobs) {
        $filterArgs += @("--path-glob", $pattern)
    }
    $filterArgs += "--invert-paths"

    Advance-StepProgress -Status "Rewrite lich su bang git-filter-repo"
    Write-Step "Xoa lich su cua cac file khop pattern"
    & $filterRepo @filterArgs
    if ($LASTEXITCODE -ne 0) {
        throw "git-filter-repo that bai."
    }

    if ($originUrl) {
        Advance-StepProgress -Status "Khoi phuc remote origin"
        Write-Step "Khoi phuc remote origin"
        Invoke-Git -Arguments @("remote", "add", "origin", $originUrl)
    } else {
        Advance-StepProgress -Status "Khong co remote origin de khoi phuc"
    }

    Advance-StepProgress -Status "Khoi phuc lai bo file hien tai"
    Write-Step "Khoi phuc lai bo file hien tai"
    Restore-SnapshotFiles -SnapshotRoot $snapshotPath -Paths $headPaths

    Advance-StepProgress -Status "Stage va commit lai cac file hien tai"
    Write-Step "Stage va commit bo file hien tai duoi Git LFS"
    Invoke-Git -Arguments @("add", "-A")
    Invoke-Git -Arguments @("commit", "-m", "Restore current large files after history cleanup")

    Advance-StepProgress -Status "Thu gon object database"
    Write-Step "Thu gon object database"
    Invoke-Git -Arguments @("reflog", "expire", "--expire=now", "--all")
    Invoke-Git -Arguments @("gc", "--prune=now", "--aggressive")

    if ($PushCurrentBranch) {
        if (-not $originUrl) {
            throw "Khong co remote origin de push."
        }

        Advance-StepProgress -Status "Push force branch hien tai len origin"
        Write-Step "Push force branch $currentBranch len origin"
        Invoke-Git -Arguments @("push", "--force", "origin", $currentBranch)
    }

    Advance-StepProgress -Status "Do dung luong repo sau khi toi uu"
    Show-RepoSizeReport -Label "Sau khi toi uu"

    Finish-StepProgress
    Write-Step "Hoan tat"
    Write-Host "Backup mirror: $backupMirrorPath"
    Write-Host "Snapshot files: $snapshotPath"
    Write-Host "Branch hien tai: $currentBranch"
}
catch {
    Finish-StepProgress
    Write-Host ""
    Write-Host "[Loi]" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
}
finally {
    if ($script:IsInteractiveSession) {
        [void](Read-Host "Nhan Enter de thoat")
    }
}
