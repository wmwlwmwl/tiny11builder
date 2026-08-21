# 清理 scratchdir 残留目录
# 删除方式与 tiny11maker / tiny11Coremaker 一致:自提权 -> 卸载残留 -> 取所有权 -> 授权 -> Remove-Item
param(
    [string[]]$Path
)

if (-not $Path) {
    $Path = @('C:\scratchdir', (Join-Path $PSScriptRoot 'scratchdir'))
}

#---------[ 自提权(与构建脚本一致) ]---------
$myWindowsID = [System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal = New-Object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole = [System.Security.Principal.WindowsBuiltInRole]::Administrator
if (-not $myWindowsPrincipal.IsInRole($adminRole)) {
    Write-Host "正在以管理员身份在新窗口重启,当前窗口可关闭。"
    $newProcess = New-Object System.Diagnostics.ProcessStartInfo 'PowerShell'
    $newProcess.Arguments = $myInvocation.MyCommand.Definition
    $newProcess.Verb = 'runas'
    [System.Diagnostics.Process]::Start($newProcess)
    exit
}

# 卸载上次中断可能残留的注册表挂载
foreach ($hive in 'zCOMPONENTS', 'zDEFAULT', 'zNTUSER', 'zSOFTWARE', 'zSYSTEM') {
    & reg unload "HKLM\$hive" 2>$null | Out-Null
}

foreach ($dir in $Path) {
    if (-not (Test-Path $dir)) {
        Write-Host "不存在,跳过: $dir"
        continue
    }
    Write-Host "处理: $dir"
    # 若仍是挂载中的镜像先卸载(丢弃更改)
    try { Dismount-WindowsImage -Path $dir -Discard -ErrorAction Stop | Out-Null } catch { }
    cmd /c takeown /f $dir /r /d y 2>&1 | Out-Null
    cmd /c icacls $dir /grant '*S-1-5-32-544:(OI)(CI)F' /t /c 2>&1 | Out-Null
    cmd /c attrib -r -s -h "$dir\*.*" /s /d 2>&1 | Out-Null
    try {
        Remove-Item -Path $dir -Recurse -Force -ErrorAction Stop
        Write-Host "已删除: $dir"
    } catch {
        Write-Host "删除失败: $($_.Exception.Message)"
    }
}
Write-Host '完成。'
