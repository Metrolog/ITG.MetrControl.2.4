﻿<# 
.Synopsis 
    Скрипт подготовки среды сборки и тестирования проекта
.Description 
    Скрипт подготовки среды сборки и тестирования проекта.
    Используется в том числе и для подготовки среды на серверах appveyor.
.Link 
    https://github.com/Metrolog/ITG.MetrControl.2.4
.Example 
    .\install.ps1 -GUI;
    Устанавливаем необходимые пакеты, в том числе - и графические среды.
#> 
[CmdletBinding(
    SupportsShouldProcess = $true
    , ConfirmImpact = 'Medium'
    , HelpUri = 'https://github.com/Metrolog/ITG.MetrControl.2.4'
)]
 
param (
    # Ключ, определяющий необходимость установки визуальных средств.
    # По умолчанию устанавливаются только средства для командной строки.
    [Switch]
    $GUI
) 

Function Execute-ExternalInstaller {
    [CmdletBinding(
        SupportsShouldProcess = $true
        , ConfirmImpact = 'Medium'
    )]
    param (
        [String]
        $LiteralPath
        ,
        [String]
        $ArgumentList
    )

    $pinfo = [System.Diagnostics.ProcessStartInfo]::new();
    $pinfo.FileName = $LiteralPath;
    $pinfo.RedirectStandardError = $true;
    $pinfo.RedirectStandardOutput = $true;
    $pinfo.RedirectStandardInput = $true;
    $pinfo.UseShellExecute = $false;
    $pinfo.Arguments = $ArgumentList;
    $p = [System.Diagnostics.Process]::new();
    try {
        $p.StartInfo = $pinfo;
        $p.Start() | Out-Null;
        $p.WaitForExit();
        $LASTEXITCODE = $p.ExitCode;
        $p.StandardOutput.ReadToEnd() `
        | Write-Output `
        ;
        if ( $p.ExitCode -ne 0 ) {
            $p.StandardError.ReadToEnd() `
            | Write-Error `
            ;
        };
    } finally {
        $p.Close();
    };
}

switch ( $env:PROCESSOR_ARCHITECTURE ) {
    'amd64' { $ArchPath = 'x64'; }
    'x86'   { $ArchPath = 'x86'; }
    default { Write-Error 'Unsupported processor architecture.'}
};
$ToPath = @();

if ( 
    ( -not ( $env:APPVEYOR -eq 'True' ) ) `
    -and ( -not $env:ChocolateyInstall ) `
) {
    Invoke-WebRequest -Uri 'https://chocolatey.org/install.ps1' -UseBasicParsing | Invoke-Expression;
};

& choco install GitVersion.Portable --confirm --failonstderr | Out-String -Stream | Write-Verbose;
& choco install GitReleaseNotes.Portable --confirm --failonstderr | Out-String -Stream | Write-Verbose;

if ( -not ( $env:APPVEYOR -eq 'True' ) ) {
    & choco install visualstudio2015community --confirm --failonstderr | Out-String -Stream | Write-Verbose;
    & choco install NuGet.CommandLine --confirm --failonstderr | Out-String -Stream | Write-Verbose;
    & choco install git --confirm --failonstderr | Out-String -Stream | Write-Verbose;
    & choco install openssl --confirm --failonstderr | Out-String -Stream | Write-Verbose;
    & choco install windows-sdk-10 --confirm --failonstderr | Out-String -Stream | Write-Verbose;
    & choco install wixtoolset --confirm --failonstderr | Out-String -Stream | Write-Verbose;
};

& choco install cygwin --confirm --failonstderr | Out-String -Stream | Write-Verbose;
$env:CygWin = Get-ItemPropertyValue `
    -Path HKLM:\SOFTWARE\Cygwin\setup `
    -Name rootdir `
;
Write-Verbose "CygWin root directory: $env:CygWin";
$ToPath += "$env:CygWin\bin";

#& choco install make mkdir touch zip --source cygwin --confirm --failonstderr | Out-String -Stream | Write-Verbose;
# исправляем проблемы совместимости chocolatey, cyg-get и cygwin
If ( Test-Path "$env:CygWin\cygwinsetup.exe" ) {
    $cygwinsetup = "$env:CygWin\cygwinsetup.exe";
} ElseIf ( Test-Path "$env:CygWin\setup-x86_64.exe" ) {
    $cygwinsetup = "$env:CygWin\setup-x86_64.exe";
} ElseIf ( Test-Path "$env:CygWin\setup-x86.exe" ) {
    $cygwinsetup = "$env:CygWin\setup-x86.exe";
} ElseIf ( Test-Path "$env:ChocolateyPath\lib\Cygwin\tools\cygwin\cygwinsetup.exe" ) {
    $cygwinsetup = "$env:ChocolateyPath\lib\Cygwin\tools\cygwin\cygwinsetup.exe";
} ElseIf ( Test-Path "$env:ChocolateyPath\lib\Cygwin.$(( Get-Package -Name CygWin -ProviderName Chocolatey ).Version)\tools\cygwin\cygwinsetup.exe" ) {
    $cygwinsetup = "$env:ChocolateyPath\lib\Cygwin.$(( Get-Package -Name CygWin -ProviderName Chocolatey ).Version)\tools\cygwin\cygwinsetup.exe";
} Else {
    Write-Error 'I can not find CygWin setup!';
};
Write-Verbose "CygWin setup: $cygwinsetup";
if ($PSCmdLet.ShouldProcess('CygWin', 'Установить переменную окружения')) {
    [System.Environment]::SetEnvironmentVariable( 'CygWin', $env:CygWin, [System.EnvironmentVariableTarget]::Machine );
};
$ToPath += "$env:CygWin\bin";

Write-Verbose 'Install CygWin tools...';
if ($PSCmdLet.ShouldProcess('make,mkdir,touch', 'Установить пакет CygWin')) {
    Execute-ExternalInstaller `
        -LiteralPath $cygwinsetup `
        -ArgumentList '--packages make,mkdir,touch --quiet-mode --no-desktop --no-startmenu --site http://mirrors.kernel.org/sourceware/cygwin/' `
    ;
};

if ( $GUI ) {
    & choco install SourceTree --confirm --failonstderr | Out-String -Stream | Write-Verbose;
    & choco install notepadplusplus --confirm --failonstderr | Out-String -Stream | Write-Verbose;
};

Write-Verbose 'Preparing PATH environment variable...';
if ($PSCmdLet.ShouldProcess('PATH', 'Установить переменную окружения')) {
    $Path = `
        ( `
            ( ( [Environment]::GetEnvironmentVariable( 'PATH', [System.EnvironmentVariableTarget]::Process ) ) -split ';' ) `
            + $ToPath `
            | Sort-Object -Unique `
        ) `
    ;
    Write-Verbose 'Path variable:';
    $Path | % { Write-Verbose "    $_" };
    $env:Path = $Path -join ';';
    [System.Environment]::SetEnvironmentVariable( 'PATH', $env:Path, [System.EnvironmentVariableTarget]::User );
};
