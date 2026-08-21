# tiny11 Core 构建脚本(汉化版)
if ((Get-ExecutionPolicy) -eq 'Restricted') {
    Write-Host "当前执行策略为 Restricted,无法运行脚本。是否改为 RemoteSigned?(yes/no)"
    $response = Read-Host
    if ($response -eq 'yes') { Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Confirm:$false }
    else { Write-Host "未修改执行策略则无法运行,正在退出..."; exit }
}
# 检查权限,非管理员则提权重启
$adminSID = New-Object System.Security.Principal.SecurityIdentifier("S-1-5-32-544")
$adminGroup = $adminSID.Translate([System.Security.Principal.NTAccount])
$myWindowsID=[System.Security.Principal.WindowsIdentity]::GetCurrent()
$myWindowsPrincipal=new-object System.Security.Principal.WindowsPrincipal($myWindowsID)
$adminRole=[System.Security.Principal.WindowsBuiltInRole]::Administrator
if (! $myWindowsPrincipal.IsInRole($adminRole))
{
    Write-Host "正在以管理员身份在新窗口重启,当前窗口可关闭。"
    $newProcess = new-object System.Diagnostics.ProcessStartInfo "PowerShell";
    $newProcess.Arguments = $myInvocation.MyCommand.Definition;
    $newProcess.Verb = "runas";
    [System.Diagnostics.Process]::Start($newProcess);
    exit
}

#---------[ 自定义配置 ]---------
# 读取 config.json,不存在或非法值时回退默认(全部开启)。GUI 也读写该文件。
function Get-Tiny11Config {
    param([string]$Path)
    $default = @{
        'apps'=$true;'edge'=$true;'onedrive'=$true;
        'systemPackages'=$true;'winre'=$true;'trimWinSxS'=$true;'disableUpdates'=$true;
        'bypassRequirements'=$true;'disableSponsoredApps'=$true;'disableTelemetry'=$true;
        'localAccount'=$true;'disableReserves'=$true;'disableBitLocker'=$true;'disableChat'=$true;
        'disableCopilot'=$true;'blockWebApps'=$true;'deleteTelemetryTasks'=$true
    }
    $cfg = @{}
    if (Test-Path -Path $Path) {
        try {
            $loaded = Get-Content -Path $Path -Raw -Encoding UTF8 | ConvertFrom-Json
            foreach ($k in $loaded.PSObject.Properties.Name) { $cfg[$k] = $loaded.$k }
        } catch { Write-Warning "config.json 读取失败,已使用默认配置:$_" }
    } else { Write-Warning "未找到 config.json,已使用默认配置(全部开启)。" }
    foreach ($k in $default.Keys) {
        if ($null -eq $cfg[$k] -or $cfg[$k] -notin $true,$false) { $cfg[$k] = $default[$k] }
    }
    return $cfg
}
$config = Get-Tiny11Config -Path "$PSScriptRoot\config.json"

Start-Transcript -Path "$PSScriptRoot\tiny11.log"
Write-Host "欢迎使用 tiny11 Core 构建工具!(BETA 05-09-25)"
Write-Host "此脚本将生成深度精简的 Windows 11 镜像。注意:精简后无法再添加语言包、更新或功能,仅适合快速测试或虚拟机环境。"
Write-Host "是否继续?(y/n)"
$input = Read-Host
if ($input -eq 'y') {
Write-Host "开始处理..."
Start-Sleep -Seconds 3
Clear-Host
$mainOSDrive = $env:SystemDrive
$hostArchitecture = $Env:PROCESSOR_ARCHITECTURE
New-Item -ItemType Directory -Force -Path "$mainOSDrive\tiny11\sources" > $null
$DriveLetter = Read-Host "请输入 Windows 11 镜像所在盘符"
$DriveLetter = $DriveLetter + ":"
if ((Test-Path "$DriveLetter\sources\boot.wim") -eq $false -or (Test-Path "$DriveLetter\sources\install.wim") -eq $false) {
    if ((Test-Path "$DriveLetter\sources\install.esd") -eq $true) {
        Write-Host "检测到 install.esd,正在转换为 install.wim..."
        & 'dism' '/English' "/Get-WimInfo" "/wimfile:$DriveLetter\sources\install.esd"
        $index = Read-Host "请输入镜像索引(Image Index)"
        Write-Host ' '
        Write-Host '正在转换,可能需要较长时间...'
        & 'DISM' /Export-Image /SourceImageFile:"$DriveLetter\sources\install.esd" /SourceIndex:$index /DestinationImageFile:"$mainOSDrive\tiny11\sources\install.wim" /Compress:max /CheckIntegrity
    } else {
        Write-Host "指定盘符中未找到 Windows 安装文件,请检查盘符。"; exit
    }
}
Write-Host "正在复制 Windows 镜像..."
Copy-Item -Path "$DriveLetter\*" -Destination "$mainOSDrive\tiny11" -Recurse -Force > $null
Set-ItemProperty -Path "$mainOSDrive\tiny11\sources\install.esd" -Name IsReadOnly -Value $false > $null 2>&1
Remove-Item "$mainOSDrive\tiny11\sources\install.esd" > $null 2>&1
Write-Host "复制完成!"
Start-Sleep -Seconds 2
Clear-Host
Write-Host "正在获取镜像信息:"
& 'dism' '/English' "/Get-WimInfo" "/wimfile:$mainOSDrive\tiny11\sources\install.wim"
$index = Read-Host "请输入镜像索引(Image Index)"
Write-Host "正在挂载 Windows 镜像,可能需要较长时间。"
$wimFilePath = "$($env:SystemDrive)\tiny11\sources\install.wim"
& takeown "/F" $wimFilePath
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
try { Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false -ErrorAction Stop } catch { }
New-Item -ItemType Directory -Force -Path "$mainOSDrive\scratchdir" > $null
& dism /English "/mount-image" "/imagefile:$($env:SystemDrive)\tiny11\sources\install.wim" "/index:$index" "/mountdir:$($env:SystemDrive)\scratchdir"
$imageIntl = & dism /English /Get-Intl "/Image:$($env:SystemDrive)\scratchdir"
$languageCode = $null
foreach ($line in ($imageIntl -split '\r?\n')) {
    if ($line -match 'Default system UI language\s*:\s*([a-zA-Z]{2}-[a-zA-Z]{2})') { $languageCode = $Matches[1]; break }
}
if ($languageCode) { Write-Host "默认系统 UI 语言代码: $languageCode" }
else { Write-Host "未能检测到系统 UI 语言代码,语言相关可选包将不被移除。" }
$imageInfo = & 'dism' '/English' '/Get-WimInfo' "/wimFile:$($env:SystemDrive)\tiny11\sources\install.wim" "/index:$index"
$architecture = $null
foreach ($line in ($imageInfo -split '\r?\n')) {
    if ($line -match 'Architecture\s*:\s*(\S+)') { $architecture = $Matches[1]; break }
}
if ($architecture -eq 'x64') { $architecture = 'amd64' }
if ($architecture) { Write-Host "系统架构: $architecture" }
else { Write-Host "未能检测到系统架构,无法继续精简 WinSxS。"; exit 1 }
if ($config.apps) {
Write-Host "挂载完成!正在移除应用..."
$packages = & 'dism' '/English' "/image:$($env:SystemDrive)\scratchdir" '/Get-ProvisionedAppxPackages' | ForEach-Object { if ($_ -match 'PackageName : (.*)') { $matches[1] } }
$packagePrefixes = 'Clipchamp.Clipchamp_','Microsoft.BingNews_','Microsoft.BingWeather_','Microsoft.GamingApp_','Microsoft.GetHelp_','Microsoft.Getstarted_','Microsoft.MicrosoftOfficeHub_','Microsoft.MicrosoftSolitaireCollection_','Microsoft.People_','Microsoft.PowerAutomateDesktop_','Microsoft.Todos_','Microsoft.WindowsAlarms_','microsoft.windowscommunicationsapps_','Microsoft.WindowsFeedbackHub_','Microsoft.WindowsMaps_','Microsoft.WindowsSoundRecorder_','Microsoft.Xbox.TCUI_','Microsoft.XboxGamingOverlay_','Microsoft.XboxGameOverlay_','Microsoft.XboxSpeechToTextOverlay_','Microsoft.YourPhone_','Microsoft.ZuneMusic_','Microsoft.ZuneVideo_','MicrosoftCorporationII.MicrosoftFamily_','MicrosoftCorporationII.QuickAssist_','MicrosoftTeams_','Microsoft.549981C3F5F10_','Microsoft.Windows.Copilot','MSTeams_','Microsoft.OutlookForWindows_','Microsoft.Windows.Teams_','Microsoft.Copilot_'
$packagesToRemove = $packages | Where-Object {
    $n = $_; $hit = $false
    foreach ($p in $packagePrefixes) { if ($n -like "$p*") { $hit=$true; break } }
    $hit
}
foreach ($package in $packagesToRemove) { Write-Host "正在移除 $package :"; & 'dism' '/English' "/image:$($env:SystemDrive)\scratchdir" '/Remove-ProvisionedAppxPackage' "/PackageName:$package" }
}
if ($config.systemPackages) {
Write-Host "应用移除完成!继续移除系统包..."
Start-Sleep -Seconds 1
Clear-Host
$scratchDir = "$($env:SystemDrive)\scratchdir"
$packagePatterns = @("Microsoft-Windows-InternetExplorer-Optional-Package~31bf3856ad364e35","Microsoft-Windows-Kernel-LA57-FoD-Package~31bf3856ad364e35~amd64","Microsoft-Windows-LanguageFeatures-Handwriting-$languageCode-Package~31bf3856ad364e35","Microsoft-Windows-LanguageFeatures-OCR-$languageCode-Package~31bf3856ad364e35","Microsoft-Windows-LanguageFeatures-Speech-$languageCode-Package~31bf3856ad364e35","Microsoft-Windows-LanguageFeatures-TextToSpeech-$languageCode-Package~31bf3856ad364e35","Microsoft-Windows-MediaPlayer-Package~31bf3856ad364e35","Microsoft-Windows-Wallpaper-Content-Extended-FoD-Package~31bf3856ad364e35","Windows-Defender-Client-Package~31bf3856ad364e35~","Microsoft-Windows-WordPad-FoD-Package~","Microsoft-Windows-TabletPCMath-Package~","Microsoft-Windows-StepsRecorder-Package~")
$allPackages = & dism /image:$scratchDir /Get-Packages /Format:Table
$allPackages = $allPackages -split "`n" | Select-Object -Skip 1
foreach ($packagePattern in $packagePatterns) {
    $packagesToRemove = $allPackages | Where-Object { $_ -like "$packagePattern*" }
    foreach ($package in $packagesToRemove) { $packageIdentity = ($package -split "\s+")[0]; Write-Host "正在移除 $packageIdentity..."; & dism /image:$scratchDir /Remove-Package /PackageName:$packageIdentity }
}
Write-Host "是否启用 .NET 3.5?镜像创建后无法再启用。(y/n)"
$input = Read-Host
if ($input -eq 'y') { Write-Host "正在启用 .NET 3.5..."; & 'dism' "/image:$scratchDir" '/enable-feature' '/featurename:NetFX3' '/All' "/source:$($env:SystemDrive)\tiny11\sources\sxs"; Write-Host ".NET 3.5 已启用。" }
elseif ($input -eq 'n') { Write-Host "未启用 .NET 3.5,继续..." }
else { Write-Host "输入无效,请输入 y 或 n。" }
}
if ($config.edge) {
Write-Host "正在移除 Edge:"
# ponytail: WebView 目录内的文件带硬链接保护,个别文件删不掉属正常,失败即跳过,避免中断后续构建。
Remove-Item -Path "$mainOSDrive\scratchdir\Program Files (x86)\Microsoft\Edge" -Recurse -Force -ErrorAction SilentlyContinue > $null
Remove-Item -Path "$mainOSDrive\scratchdir\Program Files (x86)\Microsoft\EdgeUpdate" -Recurse -Force -ErrorAction SilentlyContinue > $null
Remove-Item -Path "$mainOSDrive\scratchdir\Program Files (x86)\Microsoft\EdgeCore" -Recurse -Force -ErrorAction SilentlyContinue > $null
if ($architecture -eq 'amd64') { $folderPath = Get-ChildItem -Path "$mainOSDrive\scratchdir\Windows\WinSxS" -Filter "amd64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName }
elseif ($architecture -eq 'arm64') { $folderPath = Get-ChildItem -Path "$mainOSDrive\scratchdir\Windows\WinSxS" -Filter "arm64_microsoft-edge-webview_31bf3856ad364e35*" -Directory | Select-Object -ExpandProperty FullName }
else { $folderPath = $null; Write-Host "无法识别的架构: $architecture" }
if ($folderPath) { & 'takeown' '/f' $folderPath '/r' > $null; & icacls $folderPath "/grant" "$($adminGroup.Value):(F)" '/T' '/C' > $null; try { Remove-Item -Path $folderPath -Recurse -Force -ErrorAction Stop } catch { Write-Warning "WinSxS 中部分 Edge WebView 文件无法删除(硬链接保护),已跳过,不影响精简结果。" } }
else { Write-Host "未找到 Edge WebView 文件夹。" }
& 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/r' > $null
& 'icacls' "$mainOSDrive\scratchdir\Windows\System32\Microsoft-Edge-Webview" '/grant' "$($adminGroup.Value):(F)" '/T' '/C' > $null
try { Remove-Item -Path "$mainOSDrive\scratchdir\Windows\System32\Microsoft-Edge-Webview" -Recurse -Force -ErrorAction Stop } catch { Write-Warning "System32 中部分 Edge WebView 文件无法删除,已跳过。" }
}
if ($config.winre) {
Write-Host "正在移除 WinRE..."
& 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\System32\Recovery" '/r'
& 'icacls' "$mainOSDrive\scratchdir\Windows\System32\Recovery" '/grant' 'Administrators:F' '/T' '/C'
Remove-Item -Path "$mainOSDrive\scratchdir\Windows\System32\Recovery\winre.wim" -Recurse -Force
New-Item -Path "$mainOSDrive\scratchdir\Windows\System32\Recovery\winre.wim" -ItemType File -Force
}
if ($config.onedrive) {
Write-Host "正在移除 OneDrive:"
$oneDrivePath = "$mainOSDrive\scratchdir\Windows\System32\OneDriveSetup.exe"
if (Test-Path -Path $oneDrivePath) {
    & 'takeown' '/f' $oneDrivePath > $null
    & 'icacls' $oneDrivePath '/grant' "$($adminGroup.Value):(F)" '/T' '/C' > $null
    Remove-Item -Path $oneDrivePath -Force > $null
} else {
    Write-Host "未检测到 OneDriveSetup.exe,跳过(部分架构的原版镜像没有该文件)。"
}
}
Write-Host "移除完成!"
Start-Sleep -Seconds 2
Clear-Host
if ($config.trimWinSxS) {
Write-Host "正在获取 WinSxS 所有权,可能需要较长时间..."
& 'takeown' '/f' "$mainOSDrive\scratchdir\Windows\WinSxS" '/r'
& 'icacls' "$mainOSDrive\scratchdir\Windows\WinSxS" '/grant' "$($adminGroup.Value):(F)" '/T' '/C'
Write-Host "完成!"
Start-Sleep -Seconds 2
Clear-Host
Write-Host "正在准备精简 WinSxS..."
$folderPath = Join-Path -Path $mainOSDrive -ChildPath "\scratchdir\Windows\WinSxS_edit"
$sourceDirectory = "$mainOSDrive\scratchdir\Windows\WinSxS"
$destinationDirectory = "$mainOSDrive\scratchdir\Windows\WinSxS_edit"
New-Item -Path $folderPath -ItemType Directory
if ($architecture -eq "amd64") {
    $dirsToCopy = @(
        "x86_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "x86_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "x86_microsoft-windows-s..ngstack-onecorebase_31bf3856ad364e35_*",
        "x86_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*",
        "x86_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "x86_microsoft-windows-servicingstack-inetsrv_*",
        "x86_microsoft-windows-servicingstack-onecore_*",
        "amd64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "amd64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "amd64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "amd64_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "amd64_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "amd64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "amd64_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "amd64_microsoft-windows-s..stack-inetsrv-extra_31bf3856ad364e35_*",
        "amd64_microsoft-windows-s..stack-msg.resources_31bf3856ad364e35_*",
        "amd64_microsoft-windows-s..stack-termsrv-extra_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*",
        "amd64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*",
        "Catalogs","FileMaps","Fusion","InstallTemp","Manifests",
        "x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*"
    )
}
elseif ($architecture -eq "arm64") {
    $dirsToCopy = @(
        "arm64_microsoft-windows-servicingstack-onecore_31bf3856ad364e35_*",
        "Catalogs","FileMaps","Fusion","InstallTemp","Manifests","SettingsManifests","Temp",
        "x86_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "x86_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "x86_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "x86_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "x86_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "x86_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "arm_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "arm_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "arm_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "arm_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm64_microsoft.vc80.crt_1fc8b3b9a1e18e3b_*",
        "arm64_microsoft.vc90.crt_1fc8b3b9a1e18e3b_*",
        "arm64_microsoft.windows.c..-controls.resources_6595b64144ccf1df_*",
        "arm64_microsoft.windows.common-controls_6595b64144ccf1df_*",
        "arm64_microsoft.windows.gdiplus_6595b64144ccf1df_*",
        "arm64_microsoft.windows.i..utomation.proxystub_6595b64144ccf1df_*",
        "arm64_microsoft.windows.isolationautomation_6595b64144ccf1df_*",
        "arm64_microsoft-windows-servicing-adm_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingcommon_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicing-onecore-uapi_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack-inetsrv_31bf3856ad364e35_*",
        "arm64_microsoft-windows-servicingstack-msg_31bf3856ad364e35_*"
    )
}
foreach ($dir in $dirsToCopy) {
    $sourceDirs = Get-ChildItem -Path $sourceDirectory -Filter $dir -Directory
    foreach ($sourceDir in $sourceDirs) { $destDir = Join-Path -Path $destinationDirectory -ChildPath $sourceDir.Name; Write-Host "正在复制 $($sourceDir.Name)..."; Copy-Item -Path $sourceDir.FullName -Destination $destDir -Recurse -Force }
}
Write-Host "正在删除 WinSxS,可能需要较长时间..."
Remove-Item -Path $mainOSDrive\scratchdir\Windows\WinSxS -Recurse -Force
Rename-Item -Path $mainOSDrive\scratchdir\Windows\WinSxS_edit -NewName $mainOSDrive\scratchdir\Windows\WinSxS
Write-Host "完成!"
}
Write-Host "正在加载注册表..."
reg load HKLM\zCOMPONENTS $mainOSDrive\scratchdir\Windows\System32\config\COMPONENTS | Out-Null
reg load HKLM\zDEFAULT $mainOSDrive\scratchdir\Windows\System32\config\default | Out-Null
reg load HKLM\zNTUSER $mainOSDrive\scratchdir\Users\Default\ntuser.dat | Out-Null
reg load HKLM\zSOFTWARE $mainOSDrive\scratchdir\Windows\System32\config\SOFTWARE | Out-Null
reg load HKLM\zSYSTEM $mainOSDrive\scratchdir\Windows\System32\config\SYSTEM | Out-Null
if ($config.bypassRequirements) {
Write-Host "正在绕过系统要求(作用于系统镜像):"
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassTPMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
if ($config.disableSponsoredApps) {
Write-Host "正在禁用推广应用:"
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'OemPreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SilentInstalledAppsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableWindowsConsumerFeatures' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'ContentDeliveryAllowed' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\PolicyManager\current\device\Start' '/v' 'ConfigureStartPins' '/t' 'REG_SZ' '/d' '{"pinnedList": [{}]}' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'FeatureManagementEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'PreInstalledAppsEverEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SoftLandingEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContentEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-310093Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338388Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338389Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-338393Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-353694Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SubscribedContent-353696Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager' '/v' 'SystemPaneSuggestionsEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\PushToInstall' '/v' 'DisablePushToInstall' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\MRT' '/v' 'DontOfferThroughWUAU' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\Subscriptions' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager\SuggestedApps' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableConsumerAccountStateContent' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\CloudContent' '/v' 'DisableCloudOptimizedContent' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
if ($config.localAccount) {
Write-Host "正在启用 OOBE 本地账户:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\OOBE' '/v' 'BypassNRO' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$mainOSDrive\scratchdir\Windows\System32\Sysprep\autounattend.xml" -Force | Out-Null
}
if ($config.disableReserves) {
Write-Host "正在禁用保留空间:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\ReserveManager' '/v' 'ShippedWithReserves' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
}
if ($config.disableBitLocker) {
Write-Host "正在禁用 BitLocker 设备加密:"
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Control\BitLocker' '/v' 'PreventDeviceEncryption' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
if ($config.disableChat) {
Write-Host "正在禁用聊天图标:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Chat' '/v' 'ChatIcon' '/t' 'REG_DWORD' '/d' '3' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced' '/v' 'TaskbarMn' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
}
if ($config.edge) {
Write-Host "正在移除 Edge 相关注册表:"
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge" /f | Out-Null
reg delete "HKEY_LOCAL_MACHINE\zSOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\Microsoft Edge Update" /f | Out-Null
}
if ($config.onedrive) {
Write-Host "正在禁用 OneDrive 文件夹备份:"
& 'reg' 'add' "HKLM\zSOFTWARE\Policies\Microsoft\Windows\OneDrive" '/v' 'DisableFileSyncNGSC' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
if ($config.disableTelemetry) {
Write-Host "正在禁用遥测:"
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo' '/v' 'Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Windows\CurrentVersion\Privacy' '/v' 'TailoredExperiencesWithDiagnosticDataEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Speech_OneCore\Settings\OnlineSpeechPrivacy' '/v' 'HasAccepted' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Input\TIPC' '/v' 'Enabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' '/v' 'RestrictImplicitInkCollection' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization' '/v' 'RestrictImplicitTextCollection' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\InputPersonalization\TrainedDataStore' '/v' 'HarvestContacts' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zNTUSER\Software\Microsoft\Personalization\Settings' '/v' 'AcceptedPrivacyPolicy' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\DataCollection' '/v' 'AllowTelemetry' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\dmwappushservice' '/v' 'Start' '/t' 'REG_DWORD' '/d' '4' '/f' | Out-Null
}
if ($config.blockWebApps) {
Write-Host "正在阻止安装 DevHome 和 Outlook:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\OutlookUpdate' '/v' 'workCompleted' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Orchestrator\UScheduler\DevHomeUpdate' '/v' 'workCompleted' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\OutlookUpdate' '/f' | Out-Null
& 'reg' 'delete' 'HKLM\zSOFTWARE\Microsoft\WindowsUpdate\Orchestrator\UScheduler_Oobe\DevHomeUpdate' '/f' | Out-Null
}
if ($config.disableCopilot) {
Write-Host "正在禁用 Copilot:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsCopilot' '/v' 'TurnOffWindowsCopilot' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Edge' '/v' 'HubsSidebarEnabled' '/t' 'REG_DWORD' '/d' '0' '/f' | Out-Null
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Explorer' '/v' 'DisableSearchBoxSuggestions' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
if ($config.blockWebApps) {
Write-Host "正在阻止安装 Teams:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Teams' '/v' 'DisableInstallation' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
if ($config.blockWebApps) {
Write-Host "正在阻止安装新版 Outlook:"
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\Windows Mail' '/v' 'PreventRun' '/t' 'REG_DWORD' '/d' '1' '/f' | Out-Null
}
$tasksPath = "$mainOSDrive\scratchdir\Windows\System32\Tasks"
if ($config.deleteTelemetryTasks) {
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\Microsoft Compatibility Appraiser" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Customer Experience Improvement Program" -Recurse -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Application Experience\ProgramDataUpdater" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Chkdsk\Proxy" -Force -ErrorAction SilentlyContinue
Remove-Item -Path "$tasksPath\Microsoft\Windows\Windows Error Reporting\QueueReporting" -Force -ErrorAction SilentlyContinue
}
if ($config.disableUpdates) {
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'StopWUPostOOBE1' '/t' 'REG_SZ' '/d' 'net stop wuauserv' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'StopWUPostOOBE2' '/t' 'REG_SZ' '/d' 'sc stop wuauserv' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'StopWUPostOOBE3' '/t' 'REG_SZ' '/d' 'sc config wuauserv start= disabled' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'DisbaleWUPostOOBE1' '/t' 'REG_SZ' '/d' 'reg add HKLM\SYSTEM\CurrentControlSet\Services\wuauserv /v Start /t REG_DWORD /d 4 /f' '/f'
& 'reg' 'add' "HKLM\zSOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce" '/v' 'DisbaleWUPostOOBE2' '/t' 'REG_SZ' '/d' 'reg add HKLM\SYSTEM\ControlSet001\Services\wuauserv /v Start /t REG_DWORD /d 4 /f' '/f'
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'DoNotConnectToWindowsUpdateInternetLocations' '/t' 'REG_DWORD' '/d' '1' '/f'
& 'reg' 'add' 'HKLM\zSOFTWARE\Policies\Microsoft\Windows\WindowsUpdate' '/v' 'DisableWindowsUpdateAccess' '/t' 'REG_DWORD' '/d' '1' '/f'
& 'reg' 'add' 'HKLM\zSYSTEM\ControlSet001\Services\wuauserv' '/v' 'Start' '/t' 'REG_DWORD' '/d' '4' '/f'
& 'reg' 'delete' 'HKLM\zSYSTEM\ControlSet001\Services\WaaSMedicSVC' '/f'
& 'reg' 'delete' 'HKLM\zSYSTEM\ControlSet001\Services\UsoSvc' '/f'
}
Write-Host "调整完成!正在卸载注册表..."
reg unload HKLM\zCOMPONENTS > $null
reg unload HKLM\zDEFAULT > $null
reg unload HKLM\zNTUSER > $null
reg unload HKLM\zSOFTWARE > $null
reg unload HKLM\zSYSTEM > $null
Write-Host "正在清理镜像..."
& 'dism' '/English' "/image:$mainOSDrive\scratchdir" '/Cleanup-Image' '/StartComponentCleanup' '/ResetBase' > $null
Write-Host "清理完成。正在卸载镜像..."
& 'dism' '/English' '/unmount-image' "/mountdir:$mainOSDrive\scratchdir" '/commit'
Write-Host "正在导出镜像..."
& 'dism' '/English' '/Export-Image' "/SourceImageFile:$mainOSDrive\tiny11\sources\install.wim" "/SourceIndex:$index" "/DestinationImageFile:$mainOSDrive\tiny11\sources\install2.wim" '/compress:max'
Remove-Item -Path "$mainOSDrive\tiny11\sources\install.wim" -Force > $null
Rename-Item -Path "$mainOSDrive\tiny11\sources\install2.wim" -NewName "install.wim" > $null
Write-Host "系统镜像完成,继续处理 boot.wim。"
Start-Sleep -Seconds 2
Clear-Host
Write-Host "正在挂载 boot 镜像:"
$wimFilePath = "$($env:SystemDrive)\tiny11\sources\boot.wim"
& takeown "/F" $wimFilePath > $null
& icacls $wimFilePath "/grant" "$($adminGroup.Value):(F)"
Set-ItemProperty -Path $wimFilePath -Name IsReadOnly -Value $false
& 'dism' '/English' '/mount-image' "/imagefile:$mainOSDrive\tiny11\sources\boot.wim" '/index:2' "/mountdir:$mainOSDrive\scratchdir"
reg load HKLM\zCOMPONENTS $mainOSDrive\scratchdir\Windows\System32\config\COMPONENTS
reg load HKLM\zDEFAULT $mainOSDrive\scratchdir\Windows\System32\config\default
reg load HKLM\zNTUSER $mainOSDrive\scratchdir\Users\Default\ntuser.dat
reg load HKLM\zSOFTWARE $mainOSDrive\scratchdir\Windows\System32\config\SOFTWARE
reg load HKLM\zSYSTEM $mainOSDrive\scratchdir\Windows\System32\config\SYSTEM
if ($config.bypassRequirements) {
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' > $null
& 'reg' 'add' 'HKLM\zDEFAULT\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' > $null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV1' '/t' 'REG_DWORD' '/d' '0' '/f' > $null
& 'reg' 'add' 'HKLM\zNTUSER\Control Panel\UnsupportedHardwareNotificationCache' '/v' 'SV2' '/t' 'REG_DWORD' '/d' '0' '/f' > $null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassCPUCheck' '/t' 'REG_DWORD' '/d' '1' '/f' > $null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassRAMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' > $null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassSecureBootCheck' '/t' 'REG_DWORD' '/d' '1' '/f' > $null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassStorageCheck' '/t' 'REG_DWORD' '/d' '1' '/f' > $null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\LabConfig' '/v' 'BypassTPMCheck' '/t' 'REG_DWORD' '/d' '1' '/f' > $null
& 'reg' 'add' 'HKLM\zSYSTEM\Setup\MoSetup' '/v' 'AllowUpgradesWithUnsupportedTPMOrCPU' '/t' 'REG_DWORD' '/d' '1' '/f' > $null
& 'reg' 'add' 'HKEY_LOCAL_MACHINE\zSYSTEM\Setup' '/v' 'CmdLine' '/t' 'REG_SZ' '/d' 'X:\sources\setup.exe' '/f' > $null
}
Write-Host "调整完成!正在卸载注册表..."
reg unload HKLM\zCOMPONENTS > $null
reg unload HKLM\zDEFAULT > $null
reg unload HKLM\zNTUSER > $null
reg unload HKLM\zSOFTWARE > $null
reg unload HKLM\zSYSTEM > $null
Write-Host "正在卸载镜像..."
& 'dism' '/English' '/unmount-image' "/mountdir:$mainOSDrive\scratchdir" '/commit'
Clear-Host
Write-Host "正在导出 ESD,可能需要较长时间..."
& dism /Export-Image /SourceImageFile:"$mainOSDrive\tiny11\sources\install.wim" /SourceIndex:1 /DestinationImageFile:"$mainOSDrive\tiny11\sources\install.esd" /Compress:recovery
Remove-Item "$mainOSDrive\tiny11\sources\install.wim" > $null 2>&1
Write-Host "tiny11 镜像完成,继续制作 ISO..."
Write-Host "正在复制无人值守文件,用于 OOBE 阶段绕过微软账户..."
Copy-Item -Path "$PSScriptRoot\autounattend.xml" -Destination "$mainOSDrive\tiny11\autounattend.xml" -Force
$ADKDepTools = "C:\Program Files (x86)\Windows Kits\10\Assessment and Deployment Kit\Deployment Tools\$hostArchitecture\Oscdimg"
$localOSCDIMGPath = "$PSScriptRoot\oscdimg.exe"
if ([System.IO.Directory]::Exists($ADKDepTools)) { Write-Host "使用系统 ADK 的 oscdimg.exe。"; $OSCDIMG = "$ADKDepTools\oscdimg.exe" }
else {
    Write-Host "未找到 ADK,使用随附 oscdimg.exe。"
    $url = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"
    if (-not (Test-Path -Path $localOSCDIMGPath)) {
        Write-Host "正在下载 oscdimg.exe..."
        Invoke-WebRequest -Uri $url -OutFile $localOSCDIMGPath
        if (Test-Path $localOSCDIMGPath) { Write-Host "oscdimg.exe 下载成功。" }
        else { Write-Error "oscdimg.exe 下载失败。"; exit 1 }
    } else { Write-Host "oscdimg.exe 已存在本地。" }
    $OSCDIMG = $localOSCDIMGPath
}
& "$OSCDIMG" '-m' '-o' '-u2' '-udfver102' "-bootdata:2#p0,e,b$mainOSDrive\tiny11\boot\etfsboot.com#pEF,e,b$mainOSDrive\tiny11\efi\microsoft\boot\efisys.bin" "$mainOSDrive\tiny11" "$PSScriptRoot\tiny11.iso"
Write-Host "创建完成!按任意键退出..."
Read-Host "按回车键继续"
Write-Host "正在清理..."
Remove-Item -Path "$mainOSDrive\tiny11" -Recurse -Force > $null
Remove-Item -Path "$mainOSDrive\scratchdir" -Recurse -Force > $null
Stop-Transcript
exit
}
elseif ($input -eq 'n') { Write-Host "已选择退出。"; exit }
else { Write-Host "输入无效,请输入 y 或 n。" }