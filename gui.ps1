<#
.SYNOPSIS
    tiny11builder 图形界面:可视化编辑 config.json,并启动构建脚本。

.DESCRIPTION
    使用 PowerShell 自带的 WinForms,零第三方依赖。界面通过 config.json 与
    tiny11maker.ps1 / tiny11Coremaker.ps1 交互:勾选配置项 -> 保存到 config.json ->
    启动脚本(脚本内部读取同一份 config.json 决定执行哪些操作)。

    构建脚本本身会自动提权重启到新的管理员控制台窗口,实时日志在那个窗口查看,
    因此本界面不做日志捕获(否则提权重启后输出会丢失)。

.EXAMPLE
    .\gui.ps1
#>

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# 缩放屏上若不先声明 DPI 感知,.NET Framework 的 WinForms 会被系统虚拟化缩放,
# 再叠加 AutoScaleMode(Font 缩放)导致控件坐标/尺寸错乱(勾选框折返、文字裁切)。
# PS 5.1 无 .NET Core 的 SetHighDpiMode,这里用最兼容的 user32 SetProcessDPIAware(进程级)。
Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
public static class DpiFix {
    [DllImport("user32.dll")]
    public static extern bool SetProcessDPIAware();
}
'@
[DpiFix]::SetProcessDPIAware() | Out-Null

$root = $PSScriptRoot
$configPath = Join-Path $root 'config.json'

#---------[ 配置项 -> 中文显示名 ]---------
$keyLabels = [ordered]@{
    'apps'                 = '移除预装应用'
    'edge'                 = '移除 Microsoft Edge'
    'onedrive'             = '移除 OneDrive'
    'systemPackages'       = '移除系统包(仅核心版)'
    'winre'                = '移除 WinRE 恢复环境(仅核心版)'
    'trimWinSxS'           = '精简 WinSxS(仅核心版)'
    'disableUpdates'       = '禁用 Windows Update(仅核心版)'
    'bypassRequirements'   = '绕过硬件系统要求'
    'disableSponsoredApps' = '禁用推广应用'
    'disableTelemetry'     = '禁用遥测'
    'localAccount'         = '启用本地账户(绕过微软登录)'
    'disableReserves'      = '禁用保留空间'
    'disableBitLocker'     = '禁用 BitLocker 设备加密'
    'disableChat'          = '禁用任务栏聊天图标'
    'disableCopilot'       = '禁用 Copilot'
    'blockWebApps'         = '阻止 Teams/Outlook/DevHome 自动重装'
    'deleteTelemetryTasks' = '删除遥测相关计划任务'
}

#---------[ 配置加载/保存 ]---------
function Read-Config {
    $cfg = @{}
    if (Test-Path -Path $configPath) {
        try {
            $loaded = Get-Content -Path $configPath -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in $loaded.PSObject.Properties.Name) { $cfg[$k] = [bool]$loaded.$k }
        } catch {
            [System.Windows.Forms.MessageBox]::Show("config.json 读取失败,已按默认配置显示:`n$_", 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        }
    }
    foreach ($k in $keyLabels.Keys) {
        if ($null -eq $cfg[$k]) { $cfg[$k] = $true }
    }
    return $cfg
}

function Save-Config {
    $cfg = [ordered]@{}
    foreach ($k in $keyOrder) {
        $cfg[$k] = $checkbox[$k].Checked
    }
    try {
        [System.IO.File]::WriteAllText($configPath, ($cfg | ConvertTo-Json), [System.Text.UTF8Encoding]::new($false))
        return $true
    } catch {
        [System.Windows.Forms.MessageBox]::Show("保存 config.json 失败:`n$_", 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return $false
    }
}

#---------[ 界面 ]---------
$form = New-Object System.Windows.Forms.Form
$form.Text = 'tiny11 builder 图形界面'
# AutoScaleMode=None:控件按脚本里写入的绝对像素坐标渲染,
# 不参与 Font 自动缩放,杜绝 DPI 换算造成的坐标/尺寸错乱。
$form.AutoScaleMode = [System.Windows.Forms.AutoScaleMode]::None
$form.Size = New-Object System.Drawing.Size(560, 780)
$form.StartPosition = [System.Windows.Forms.FormStartPosition]::CenterScreen
$form.MinimumSize = New-Object System.Drawing.Size(540, 780)

# 顶部:构建脚本选择
$radioMaker = New-Object System.Windows.Forms.RadioButton
$radioMaker.Text = '常规版 (tiny11maker)'
$radioMaker.AutoSize = $true
$radioMaker.Location = New-Object System.Drawing.Point(92, 15)
$form.Controls.Add($radioMaker)

$radioCore = New-Object System.Windows.Forms.RadioButton
$radioCore.Text = '核心精简版 (tiny11Coremaker)'
$radioCore.AutoSize = $true
$radioCore.Location = New-Object System.Drawing.Point(232, 15)
$form.Controls.Add($radioCore)

$lblScript = New-Object System.Windows.Forms.Label
$lblScript.Text = '构建脚本:'
$lblScript.AutoSize = $true
$lblScript.Location = New-Object System.Drawing.Point(12, 16)
$form.Controls.Add($lblScript)

# 中部:配置勾选(普通 CheckBox,绝对坐标手动布局,一次容纳全部)
$checkbox = @{}
$keyOrder = @($keyLabels.Keys)
$y = 52
foreach ($k in $keyOrder) {
    $cb = New-Object System.Windows.Forms.CheckBox
    $cb.Text = $keyLabels[$k]
    $cb.AutoSize = $true
    $cb.Location = New-Object System.Drawing.Point(20, $y)
    $cb.Checked = $true
    $form.Controls.Add($cb)
    $checkbox[$k] = $cb
    $y += 30
}

# 底部:操作按钮
$btnSave = New-Object System.Windows.Forms.Button
$btnSave.Text = '保存配置'
$btnSave.Size = New-Object System.Drawing.Size(110, 32)
$btnSave.Location = New-Object System.Drawing.Point(20, ($y + 14))
$form.Controls.Add($btnSave)

$btnBuild = New-Object System.Windows.Forms.Button
$btnBuild.Text = '保存并启动构建'
$btnBuild.Size = New-Object System.Drawing.Size(140, 32)
$btnBuild.Location = New-Object System.Drawing.Point(140, ($y + 14))
$form.Controls.Add($btnBuild)

$tip = New-Object System.Windows.Forms.Label
$tip.Text = '提示:构建脚本会自动提权到新的管理员窗口,实时日志将在那里显示。'
$tip.Size = New-Object System.Drawing.Size(260, 16)
$tip.AutoSize = $false
$tip.ForeColor = [System.Drawing.Color]::Gray
$tip.Location = New-Object System.Drawing.Point(292, 22)
$form.Controls.Add($tip)

#---------[ 行为 ]---------
$btnSave.Add_Click({
    if (Save-Config) {
        [System.Windows.Forms.MessageBox]::Show('配置已保存到 config.json。', 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    }
})

$btnBuild.Add_Click({
    if ($radioCore.Checked) { $scriptName = 'tiny11Coremaker.ps1' }
    elseif ($radioMaker.Checked) { $scriptName = 'tiny11maker.ps1' }
    else {
        [System.Windows.Forms.MessageBox]::Show('请先选择构建脚本。', 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Warning) | Out-Null
        return
    }
    $scriptPath = Join-Path $root $scriptName
    if (-not (Test-Path $scriptPath)) {
        [System.Windows.Forms.MessageBox]::Show("找不到 $scriptName 。", 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
        return
    }
    if (-not (Save-Config)) { return }

    # 提权启动构建脚本(脚本内部会自行提权重启到管理员窗口)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -File `"$scriptPath`""
    $psi.UseShellExecute = $true
    $psi.Verb = 'runas'
    $psi.WorkingDirectory = $root
    try {
        [System.Diagnostics.Process]::Start($psi) | Out-Null
        [System.Windows.Forms.MessageBox]::Show("已提权启动 $scriptName,请在弹出窗口确认权限。构建日志将在管理员控制台显示。", 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Information) | Out-Null
    } catch {
        [System.Windows.Forms.MessageBox]::Show("启动失败:`n$_", 'tiny11', [System.Windows.Forms.MessageBoxButtons]::OK, [System.Windows.Forms.MessageBoxIcon]::Error) | Out-Null
    }
})

$form.Add_Shown({
    $cfg = Read-Config
    foreach ($k in $keyOrder) {
        $checkbox[$k].Checked = $cfg[$k]
    }
})

[System.Windows.Forms.Application]::Run($form)