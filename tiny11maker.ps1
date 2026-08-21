<#
.SYNOPSIS
    用于构建精简版 Windows 11 镜像的脚本。

.DESCRIPTION
    这是为自动化构建精简版 Windows 11 镜像(类似 tiny10)而创建的脚本。
    核心目标:只使用微软官方工具(如 DISM),不依赖任何外部三方工具。
    唯一的可执行文件是 oscdimg.exe,它来自 Windows ADK,用于制作可引导 ISO 镜像。

.PARAMETER ISO
    已挂载 iso 的盘符(如: E)

.PARAMETER SCRATCH
    工作分区盘符(如: D)

.EXAMPLE
    .\tiny11maker.ps1 E D
    .\tiny11maker.ps1 -ISO E -SCRATCH D
    .\tiny11maker.ps1 -SCRATCH D -ISO E
    .\tiny11maker.ps1

    * 若使用位置参数,第一个必须是已挂载的 iso,第二个是工作分区盘符。
    建议使用完整命名参数(如 "-ISO"),这样可任意调整顺序。

.NOTES
    作者: ntdevlabs
    日期: 09-07-25
#>

#---------[ 参数 ]---------#
param (
    [ValidatePattern('^[c-zC-Z]$')][string]$ISO,
    [ValidatePattern('^[c-zC-Z]$')][string]$SCRATCH
)

if (-not $SCRATCH) {
    $ScratchDisk = $PSScriptRoot -replace '[\\]+$', ''
} else {
    $ScratchDisk = $SCRATCH + ":"
}

#---------[ 函数 ]---------#
function Set-RegistryValue {
    param (
        [string]$path,
        [string]$name,
        [string]$type,
        [string]$value
    )
    try {
        & 'reg' 'add' $path '/v' $name '/t' $type '/d' $value '/f' | Out-Null
        Write-Output "已设置注册表值: $path\$name"
    } catch {
        Write-Output "设置注册表值失败: $_"
    }
}

function Remove-RegistryValue {
    param (
		[string]$path
	)
	try {
		& 'reg' 'delete' $path '/f' | Out-Null
		Write-Output "已删除注册表值: $path"
	} catch {
		Write-Output "删除注册表值失败: $_"
	}
}

#---------[ 执行 ]---------#
# 检查 PowerShell 执行策略
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Output "当前 PowerShell 执行策略为 Restricted,无法运行脚本。是否改为 RemoteSigned?(yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') {
        Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false
    } else {
        Write-Output "不修改执行策略则无法运行脚本,正在退出..."
        exit
    }
}

# 检查权限,非管理员则提权重启
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (! $myWindowsPrincipal.IsInRole($adminRole))
{
    Write-Output "正在以管理员身份在新窗口重启 Tiny11 构建工具,当前窗口可关闭。"
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

# 若缺少 autounattend.xml,则从官方源下载
if (-not (Test-Path -Path "$PSScriptRoot/autounattend.xml")) {
    Invoke-RestMethod "https://raw.githubusercontent.com/ntdevlabs/tiny11builder/refs/heads/main/autounattend.xml" -OutFile "$PSScriptRoot/autounattend.xml"
}

# 开始记录日志并准备窗口
Start-Transcript -Path "$PSScriptRoot\tiny11_$(get-date -f yyyyMMdd_HHmms).log"

$Host.UI.RawUI.WindowTitle = "Tiny11 镜像构建工具"
Clear-Host
Write-Output "欢迎使用 tiny11 镜像构建工具!版本: 09-07-25"

$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$ScratchDisk\tiny11\sources" | Out-Null
do {
    if (-not $ISO) {
        $DriveLetter = Read-Host "请输入 Windows 11 镜像所在盘符"
    } else {
        $DriveLetter = $ISO
    }
    if ($DriveLetter -match '^[c-zC-Z]$') {
        $DriveLetter = $DriveLetter + ":"
        Write-Output "盘符已设为 $DriveLetter"
    } else {
        Write-Output "无效盘符。请输入 C 到 Z 之间的字母。"
    }
} while ($DriveLetter -notmatch '^[c-zC-Z]:$')

if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Output "检测到 install.esd,正在转换为 install.wim..."
        Get-WindowsImage -ImagePath $DriveLetter\sources\install.esd
        $index = Read-Host "请输入镜像索引(Image Index)"
        Write-Output ' '
        Write-Output '正在将 install.esd 转换为 install.wim,可能需要较长时间...'
        Export-WindowsImage -SourceImagePath $DriveLetter\sources\install.esd -SourceIndex $index -DestinationImagePath $ScratchDisk\tiny11\sources\install.wim -Compressiontype Maximum -CheckIntegrity
    } else {
        Write-Output "在指定盘符中未找到 Windows 系统安装文件。"
        Write-Output "请确认输入了正确的 DVD 盘符。"
        exit
    }
}

Write-Output "正在复制 Windows 镜像..."
Copy-Item -Path "$DriveLetter\*" -Destination "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
Set-ItemProperty -Path "$ScratchDisk\tiny11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$ScratchDisk\tiny11\sources\install.esd" > $null 2>&1
Write-Output "复制完成!"
Start-Sleep -Seconds 2
Clear-Host
Write-Output "正在获取镜像信息:"
$ImagesIndex = (Get-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim).ImageIndex
while ($ImagesIndex -notcontains $index) {
    Get-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim
    $index = Read-Host "请输入镜像索引(Image Index)"
}
Write-Output "正在挂载 Windows 镜像,可能需要较长时间。"
$wimFilePath = "$ScratchDisk\tiny11\sources\install.wim"
& takeown "/F" $wimFilePath
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try {
    Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop
} catch {
    # 忽略只读属性设置失败,继续执行
	Write-Error "$wimFilePath 未找到"
}
New-Item -ItemType Directory -Force -Path "$ScratchDisk\scratchdir" > $null
Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\install.wim -Index $index -Path $ScratchDisk\scratchdir

$imageIntl = & dism /English /Get-Intl "/Image:$($ScratchDisk)\scratchdir"
$languageCode = $null
foreach ($line in ($imageIntl -split '\r?\n')) {
    if ($line -match 'Default system UI language\s*:\s*([a-zA-Z]{2}-[a-zA-Z]{2})') { $languageCode = $Matches[1]; break }
}

if ($languageCode) {
    Write-Output "默认系统 UI 语言代码: $languageCode"
} else {
    Write-Output "未能检测到默认系统 UI 语言代码。"
}

$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($ScratchDisk)\tiny11\sources\install.wim" "/index:$index"
$architecture = $null
foreach ($line in ($imageInfo -split '\r?\n')) {
    if ($line -match 'Architecture\s*:\s*(\S+)') { $architecture = $Matches[1]; break }
}
if ($architecture -eq 'x64') { $architecture = 'amd64' }

if ($architecture) {
    Write-Output "系统架构: $architecture"
} else {
    Write-Output "未能检测到系统架构信息。"
}

Write-Output "挂载完成!正在执行应用移除..."
$packages = & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Get-ProvisionedAppxPackages' |
    ForEach-Object {
        if ($_ -match 'PackageName : (.*)') {
            $matches[1]
        }
    }

$packagePrefixes = 'AppUp.IntelManagementandSecurityStatus',
'Clipchamp.Clipchamp',
'DolbyLaboratories.DolbyAccess',
'DolbyLaboratories.DolbyDigitalPlusDecoderOEM',
'Microsoft.BingNews',
'Microsoft.BingSearch',
'Microsoft.BingWeather',
'Microsoft.Copilot',
'Microsoft.Windows.CrossDevice',
'Microsoft.GamingApp',
'Microsoft.GetHelp',
'Microsoft.Getstarted',
'Microsoft.Microsoft3DViewer',
'Microsoft.MicrosoftOfficeHub',
'Microsoft.MicrosoftSolitaireCollection',
'Microsoft.MicrosoftStickyNotes',
'Microsoft.MixedReality.Portal',
'Microsoft.MSPaint',
'Microsoft.Office.OneNote',
'Microsoft.OfficePushNotificationUtility',
'Microsoft.OutlookForWindows',
'Microsoft.Paint',
'Microsoft.People',
'Microsoft.PowerAutomateDesktop',
'Microsoft.SkypeApp',
'Microsoft.StartExperiencesApp',
'Microsoft.Todos',
'Microsoft.Wallet',
'Microsoft.Windows.DevHome',
'Microsoft.Windows.Copilot',
'Microsoft.Windows.Teams',
'Microsoft.WindowsAlarms',
'Microsoft.WindowsCamera',
'microsoft.windowscommunicationsapps',
'Microsoft.WindowsFeedbackHub',
'Microsoft.WindowsMaps',
'Microsoft.WindowsSoundRecorder',
'Microsoft.WindowsTerminal',
'Microsoft.Xbox.TCUI',
'Microsoft.XboxApp',
'Microsoft.XboxGameOverlay',
'Microsoft.XboxGamingOverlay',
'Microsoft.XboxIdentityProvider',
'Microsoft.XboxSpeechToTextOverlay',
'Microsoft.YourPhone',
'Microsoft.ZuneMusic',
'Microsoft.ZuneVideo',
'MicrosoftCorporationII.MicrosoftFamily',
'MicrosoftCorporationII.QuickAssist',
'MSTeams',
'MicrosoftTeams',
'Microsoft.WindowsTerminal',
'Microsoft.549981C3F5F10'

# 移除包名以任一前缀开头的已安装应用
$packagesToRemove = $packages | Where-Object {
    $n = $_
    $hit = $false
    foreach ($p in $packagePrefixes) { if ($n -like "$p*") { $hit = $true; break } }
    $hit
}
foreach ($package in $packagesToRemove) {
    & 'dism' '/English' "/image:$($ScratchDisk)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package"
}

Write-Output "正在移除 Edge:"
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force | Out-Null
& 'takeown' '/f' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r' | Out-Null
& 'icacls' "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force | Out-Null
Write-Output "正在移除 OneDrive:"
$oneDrivePath = "$ScratchDisk\scratchdir\Windows\System32\OneDriveSetup.exe"
if (Test-Path -Path $oneDrivePath) {
    & 'takeown' '/f' $oneDrivePath | Out-Null
    & 'icacls' $oneDrivePath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' | Out-Null
    Remove-Item -Path $oneDrivePath -Force | Out-Null
} else {
    Write-Output "未检测到 OneDriveSetup.exe,跳过(部分架构的原版镜像没有该文件)。"
}
Write-Output "移除完成!"
Start-Sleep -Seconds 2
Clear-Host
Write-Output "正在加载注册表..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM | Out-Null
Write-Output "正在绕过系统要求(作用于系统镜像):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
Write-Output "正在禁用推广应用:"
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'OemPreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SilentInstalledAppsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableWindowsConsumerFeatures' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'ContentDeliveryAllowed' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' 'ConfigureStartPins' 'REG_SZ' '{"pinnedList": [{}]}'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'FeatureManagementEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'PreInstalledAppsEverEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SoftLandingEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContentEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-310093Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338388Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338389Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-338393Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353694Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SubscribedContent-353696Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' 'SystemPaneSuggestionsEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' 'DisablePushToInstall' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' 'DontOfferThroughWUAU' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions'
Remove-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableConsumerAccountStateContent' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' 'DisableCloudOptimizedContent' 'REG_DWORD' '1'
Write-Output "正在启用 OOBE 本地账户:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' 'BypassNRO' 'REG_DWORD' '1'
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\scratchdir\Windows\System32\Sysprep\autounattend.xml" -Force | Out-Null

Write-Output "正在禁用保留空间:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' 'ShippedWithReserves' 'REG_DWORD' '0'
Write-Output "正在禁用 BitLocker 设备加密"
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' 'PreventDeviceEncryption' 'REG_DWORD' '1'
Write-Output "正在禁用聊天图标:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' 'ChatIcon' 'REG_DWORD' '3'
Set-RegistryValue 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' 'TaskbarMn' 'REG_DWORD' '0'
Write-Output "正在移除 Edge 相关注册表"
Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge"
Remove-RegistryValue "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update"
Write-Output "正在禁用 OneDrive 文件夹备份"
Set-RegistryValue "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" "DisableFileSyncNGSC" "REG_DWORD" "1"
Write-Output "正在禁用遥测:"
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' 'TailoredExperiencesWithDiagnosticDataEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' 'HasAccepted' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' 'Enabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitInkCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' 'RestrictImplicitTextCollection' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' 'HarvestContacts' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' 'AcceptedPrivacyPolicy' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' 'AllowTelemetry' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' 'Start' 'REG_DWORD' '4'
## 阻止安装 DevHome 和 Outlook
Write-Output "正在阻止安装 DevHome 和 Outlook:"
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' 'workCompleted' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' 'workCompleted' 'REG_DWORD' '1'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate'
Remove-RegistryValue 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate'
Write-Output "正在禁用 Copilot"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' 'TurnOffWindowsCopilot' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' 'HubsSidebarEnabled' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' 'DisableSearchBoxSuggestions' 'REG_DWORD' '1'
Write-Output "正在阻止安装 Teams:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' 'DisableInstallation' 'REG_DWORD' '1'
Write-Output "正在阻止安装新版 Outlook:"
Set-RegistryValue 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' 'PreventRun' 'REG_DWORD' '1'

Write-Host "正在删除计划任务定义文件..."
$tasksPath = "$ScratchDisk\scratchdir\Windows\System32\Tasks"

# 应用程序兼容性评估
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue

# 客户体验改善计划(删除整个文件夹及其所有任务)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue

# 程序数据更新器
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue

# Chkdsk 代理
Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue

# Windows 错误报告(QueueReporting)
Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
Write-Host "计划任务文件已删除。"
Write-Host "正在卸载注册表..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null
Write-Output "正在清理镜像..."
dism.exe /Image:$ScratchDisk\scratchdir /Cleanup-Image /StartComponentCleanup /ResetBase
Write-Output "清理完成。"
Write-Output ' '
Write-Output "正在卸载镜像..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save
Write-Host "正在导出镜像..."
Dism.exe /Export-Image /SourceImageFile:"$ScratchDisk\tiny11\sources\install.wim" /SourceIndex:$index /DestinationImageFile:"$ScratchDisk\tiny11\sources\install2.wim" /Compress:recovery
Remove-Item -Path "$ScratchDisk\tiny11\sources\install.wim" -Force | Out-Null
Rename-Item -Path "$ScratchDisk\tiny11\sources\install2.wim" -NewName "install.wim" | Out-Null
Write-Output "Windows 系统镜像已完成,继续处理 boot.wim。"
Start-Sleep -Seconds 2
Clear-Host
Write-Output "正在挂载 boot 镜像:"
$wimFilePath = "$ScratchDisk\tiny11\sources\boot.wim"
& takeown "/F" $wimFilePath | Out-Null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false
Mount-WindowsImage -ImagePath $ScratchDisk\tiny11\sources\boot.wim -Index 2 -Path $ScratchDisk\scratchdir
Write-Output "正在加载注册表..."
reg load HKLM\zCOMPONENTS $ScratchDisk\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $ScratchDisk\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $ScratchDisk\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $ScratchDisk\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $ScratchDisk\scratchdir\Windows\System32\config\SYSTEM

Write-Output "正在绕过系统要求(作用于安装镜像):"
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV1' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' 'SV2' 'REG_DWORD' '0'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassCPUCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassRAMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassSecureBootCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassStorageCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\LabConfig' 'BypassTPMCheck' 'REG_DWORD' '1'
Set-RegistryValue 'HKLM\zSYSTEM\Setup\MoSetup' 'AllowUpgradesWithUnsupportedTPMOrCPU' 'REG_DWORD' '1'
Write-Output "调整完成!"

Write-Output "正在卸载注册表..."
reg unload HKLM\zCOMPONENTS | Out-Null
reg unload HKLM\zDEFAULT | Out-Null
reg unload HKLM\zNTUSER | Out-Null
reg unload HKLM\zSOFTWARE | Out-Null
reg unload HKLM\zSYSTEM | Out-Null

Write-Output "正在卸载镜像..."
Dismount-WindowsImage -Path $ScratchDisk\scratchdir -Save
Clear-Host
Write-Output "tiny11 镜像已构建完成,继续制作 ISO..."
Write-Output "正在复制无人值守文件,用于 OOBE 阶段绕过微软账户..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$ScratchDisk\tiny11\autounattend.xml" -Force | Out-Null
Write-Output "正在制作 ISO 镜像..."
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"

if ([System.IO.Directory]::Exists($ADKDepTools)) {
    Write-Output "将使用系统 ADK 中的 oscdimg.exe。"
    $OSCDIMG = "$ADKDepTools\oscdimg.exe"
} else {
    Write-Output "未找到 ADK 文件夹,将使用随附的 oscdimg.exe。"
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"

    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Output "正在下载 oscdimg.exe..."
        Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath

        if (Test-Path $localOSCDIMGPath) {
            Write-Output "oscdimg.exe 下载成功。"
        } else {
            Write-Error "oscdimg.exe 下载失败。"
            exit 1
        }
    } else {
        Write-Output "oscdimg.exe 已存在于本地。"
    }

    $OSCDIMG = $localOSCDIMGPath
}

& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$ScratchDisk\tiny11\boot\etfsboot.com#pEF,e,b$ScratchDisk\tiny11\efi\microsoft\boot\efisys.bin" "$ScratchDisk\tiny11" "$PSScriptRoot\tiny11.iso"

# 收尾
Write-Output "创建完成!按任意键退出脚本..."
Read-Host "按回车键继续"
Write-Output "正在执行清理..."
Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force | Out-Null
Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force | Out-Null
Write-Output "正在弹出 ISO 盘符"
Get-Volume -DriveLetter $DriveLetter[0] | Get-DiskImage | Dismount-DiskImage
Write-Output "ISO 盘符已弹出"
Write-Output "正在移除 oscdimg.exe..."
Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
Write-Output "正在移除 autounattend.xml..."
Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue

Write-Output "清理检查:"
if (Test-Path -Path "$ScratchDisk\tiny11") {
    Write-Output "tiny11 文件夹仍存在,尝试再次删除..."
    Remove-Item -Path "$ScratchDisk\tiny11" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$ScratchDisk\tiny11") {
        Write-Output "tiny11 文件夹删除失败。"
    } else {
        Write-Output "tiny11 文件夹删除成功。"
    }
} else {
    Write-Output "tiny11 文件夹不存在,无需处理。"
}
if (Test-Path -Path "$ScratchDisk\scratchdir") {
    Write-Output "scratchdir 文件夹仍存在,尝试再次删除..."
    Remove-Item -Path "$ScratchDisk\scratchdir" -Recurse -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$ScratchDisk\scratchdir") {
        Write-Output "scratchdir 文件夹删除失败。"
    } else {
        Write-Output "scratchdir 文件夹删除成功。"
    }
} else {
    Write-Output "scratchdir 文件夹不存在,无需处理。"
}
if (Test-Path -Path "$PSScriptRoot\oscdimg.exe") {
    Write-Output "oscdimg.exe 仍存在,尝试再次删除..."
    Remove-Item -Path "$PSScriptRoot\oscdimg.exe" -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$PSScriptRoot\oscdimg.exe") {
        Write-Output "oscdimg.exe 删除失败。"
    } else {
        Write-Output "oscdimg.exe 删除成功。"
    }
} else {
    Write-Output "oscdimg.exe 不存在,无需处理。"
}
if (Test-Path -Path "$PSScriptRoot\autounattend.xml") {
    Write-Output "autounattend.xml 仍存在,尝试再次删除..."
    Remove-Item -Path "$PSScriptRoot\autounattend.xml" -Force -ErrorAction SilentlyContinue
    if (Test-Path -Path "$PSScriptRoot\autounattend.xml") {
        Write-Output "autounattend.xml 删除失败。"
    } else {
        Write-Output "autounattend.xml 删除成功。"
    }
} else {
    Write-Output "autounattend.xml 不存在,无需处理。"
}

# 终止日志记录
Stop-Transcript

exit