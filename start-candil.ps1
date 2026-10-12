<#
  CANDIL OS - Lanzador de la suite local (Windows / PowerShell 5.1+)
  ----------------------------------------------------------------
  Levanta cada herramienta ArtCraft (Rust + WebAssembly) en su puerto local.

  La suite NO es uniforme; cada repo usa su propio runner web:
    trunk  -> PhotoCraft, VectorCraft, DesignCraft, PdfCraft
              (apps/<x>-web, `trunk serve --release`, salida dist/web)
    xtask  -> FilmCraft, LightCraft, EffectCraft
              (`cargo xtask web --serve <puerto>`, salida en target/...)

  Modos:
    serve   (por defecto)  Deja las 7 apps en linea (8081-8087). Sirve al instante los
                           sitios ya compilados (dist) y solo compila lo que falte.
    dev                    Fuerza los servidores de desarrollo (trunk serve / cargo xtask),
                           recompilando cada app.
    build                  Compila cada app (sin servidor).
    static                 Sirve solo los sitios ya compilados con el server embebido de PHP.
    stop                   Detiene los servicios de los puertos 8081-8087.
    status                 Informa que herramientas estan en linea.

  Ejemplos:
    .\start-candil.ps1
    .\start-candil.ps1 build
    .\start-candil.ps1 static
    .\start-candil.ps1 stop
#>
[CmdletBinding()]
param(
    [ValidateSet('serve', 'dev', 'build', 'static', 'stop', 'status')]
    [string]$Mode = 'serve'
)

$ErrorActionPreference = 'Stop'
$Root = $PSScriptRoot
$RunDir = Join-Path $Root '_run'
if (-not (Test-Path $RunDir)) { New-Item -ItemType Directory -Path $RunDir | Out-Null }
$Router = Join-Path $Root 'tools\candil-router.php'

# Runner web por herramienta (ver AGENTS.md/docs/web.md de cada repo):
#   trunk : `trunk serve --release --port N` dentro de apps/<x>-web  -> dist/web
#   xtask : `cargo xtask web --serve N` en la raiz del repo          -> target/...
$Tools = @(
    [pscustomobject]@{ Folder = 'photocraft';  Name = 'El Retrato';  Port = 8081; Ref = 'Photoshop / PhotoCraft';     Runner = 'trunk'; Web = 'photocraft\apps\photocraft-web';   Dist = 'photocraft\dist\web' },
    [pscustomobject]@{ Folder = 'vectorcraft'; Name = 'El Cincel';   Port = 8082; Ref = 'Illustrator / VectorCraft';  Runner = 'trunk'; Web = 'vectorcraft\apps\vectorcraft-web'; Dist = 'vectorcraft\dist\web' },
    [pscustomobject]@{ Folder = 'filmcraft';   Name = 'La Tijera';   Port = 8083; Ref = 'Premiere Pro / FilmCraft';    Runner = 'xtask'; Web = 'filmcraft';                      Dist = 'filmcraft\target\web\dist' },
    [pscustomobject]@{ Folder = 'lightcraft';  Name = 'El Farol';    Port = 8084; Ref = 'Lightroom / LightCraft';      Runner = 'xtask'; Web = 'lightcraft';                     Dist = 'lightcraft\target\web-site' },
    [pscustomobject]@{ Folder = 'effectcraft'; Name = 'La Chispa';   Port = 8085; Ref = 'After Effects / EffectCraft'; Runner = 'xtask'; Web = 'effectcraft';                    Dist = 'effectcraft\target\web\dist' },
    [pscustomobject]@{ Folder = 'designcraft'; Name = 'La Imprenta'; Port = 8086; Ref = 'InDesign / DesignCraft';      Runner = 'trunk'; Web = 'designcraft\apps\designcraft-web'; Dist = 'designcraft\dist\web' },
    [pscustomobject]@{ Folder = 'pdfcraft';    Name = 'El Folleto';  Port = 8087; Ref = 'Acrobat Pro / PdfCraft';      Runner = 'trunk'; Web = 'pdfcraft\apps\pdfcraft-web';       Dist = 'pdfcraft\dist\web' }
)

function Write-Head {
    Write-Host ''
    Write-Host '  ============================================================' -ForegroundColor DarkYellow
    Write-Host '    C A N D I L   O S   -   Herramientas Criollas' -ForegroundColor Yellow
    Write-Host "    Modo: $Mode    Raiz: $Root" -ForegroundColor DarkYellow
    Write-Host '  ============================================================' -ForegroundColor DarkYellow
    Write-Host ''
}

function Get-Exe { param([string]$Name) $c = Get-Command $Name -ErrorAction SilentlyContinue; if ($c) { return $c.Source } return $null }
function Get-Cargo {
    $c = Get-Exe 'cargo'; if ($c) { return $c }
    $p = Join-Path $env:USERPROFILE '.cargo\bin\cargo.exe'; if (Test-Path $p) { return $p }
    return $null
}
function Get-Trunk {
    $t = Get-Exe 'trunk'; if ($t) { return $t }
    $p = Join-Path $env:USERPROFILE '.cargo\bin\trunk.exe'; if (Test-Path $p) { return $p }
    return $null
}
function Get-Php {
    $p = Get-Exe 'php'; if ($p) { return $p }
    foreach ($c in @('D:\XAMPP\php\php.exe', 'C:\xampp\php\php.exe')) { if (Test-Path $c) { return $c } }
    return $null
}
function Test-Port {
    param([int]$Port, [int]$TimeoutMs = 1200)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect('127.0.0.1', $Port, $null, $null)
        if ($iar.AsyncWaitHandle.WaitOne($TimeoutMs, $false) -and $client.Connected) { $client.EndConnect($iar); return $true }
        return $false
    } catch { return $false } finally { $client.Close() }
}

function Show-PrereqHelp {
    Write-Host '[!] Falta la cadena de compilacion WebAssembly.' -ForegroundColor Red
    Write-Host ''
    Write-Host '    Requisitos:' -ForegroundColor Gray
    Write-Host '      - Rust 1.95+               https://rustup.rs' -ForegroundColor Gray
    Write-Host '      - rustup target add wasm32-unknown-unknown' -ForegroundColor Gray
    Write-Host '      - cargo install --locked trunk        (solo Photo/Vector/Design/PdfCraft)' -ForegroundColor Gray
    Write-Host '      - wasm-bindgen-cli (0.2.129)          (solo Film/Light/EffectCraft)' -ForegroundColor Gray
    Write-Host ''
    Write-Host '    Sin toolchain podes servir sitios ya compilados:' -ForegroundColor Gray
    Write-Host '      .\start-candil.ps1 static' -ForegroundColor Gray
    Write-Host ''
}

function Start-Tool {
    param($Tool, [string]$Cargo, [string]$Trunk)
    $log = Join-Path $RunDir "$($Tool.Folder).log"
    if ($Tool.Runner -eq 'trunk') {
        if (-not $Trunk) { Write-Host ("  [x] {0,-12} requiere 'trunk' (no encontrado)" -f $Tool.Name) -ForegroundColor Red; return }
        $web = Join-Path $Root $Tool.Web
        if (-not (Test-Path $web)) { Write-Host ("  [x] {0,-12} falta {1}" -f $Tool.Name, $web) -ForegroundColor Red; return }
        $line = "trunk serve --release --port $($Tool.Port) --address 127.0.0.1 > `"$log`" 2>&1"
        Start-Process -FilePath 'cmd.exe' -WorkingDirectory $web -ArgumentList @('/c', $line) -WindowStyle Minimized | Out-Null
    }
    else {
        if (-not $Cargo) { Write-Host ("  [x] {0,-12} requiere 'cargo' (no encontrado)" -f $Tool.Name) -ForegroundColor Red; return }
        $repo = Join-Path $Root $Tool.Folder
        $line = "cargo xtask web --serve $($Tool.Port) > `"$log`" 2>&1"
        Start-Process -FilePath 'cmd.exe' -WorkingDirectory $repo -ArgumentList @('/c', $line) -WindowStyle Minimized | Out-Null
    }
    Write-Host ("  [>] {0,-12} -> http://localhost:{1}   ({2}; log _run\{3}.log)" -f $Tool.Name, $Tool.Port, $Tool.Runner, $Tool.Folder) -ForegroundColor Green
}

function Start-Static {
    param($Tool, [string]$Php)
    if (Test-Port -Port $Tool.Port) {
        Write-Host ("  [=] {0,-12} -> http://localhost:{1}   (ya en linea)" -f $Tool.Name, $Tool.Port) -ForegroundColor DarkGreen
        return
    }
    $dist = Join-Path $Root $Tool.Dist
    if (-not (Test-Path (Join-Path $dist 'index.html'))) {
        Write-Host ("  [.] {0,-12} sin compilar ({1}) - corre: start-candil.ps1 build" -f $Tool.Name, $Tool.Dist) -ForegroundColor DarkYellow
        return
    }
    if (-not $Php) {
        Write-Host ("  [x] {0,-12} falta PHP para servir {1}" -f $Tool.Name, $Tool.Dist) -ForegroundColor Red
        return
    }
    $log = Join-Path $RunDir "$($Tool.Folder).log"
    $a = @('-S', "127.0.0.1:$($Tool.Port)", '-t', "`"$dist`"", "`"$Router`"")
    $proc = Start-Process -FilePath $Php -WorkingDirectory $dist -ArgumentList $a -RedirectStandardOutput $log -RedirectStandardError "$log.err" -WindowStyle Hidden -PassThru
    if ($proc) { Add-Content -Path (Join-Path $RunDir 'pids.txt') -Value $proc.Id -ErrorAction SilentlyContinue }
    $ok = $false
    for ($i = 0; $i -lt 24; $i++) { Start-Sleep -Milliseconds 250; if (Test-Port -Port $Tool.Port) { $ok = $true; break } }
    if ($ok) {
        Write-Host ("  [>] {0,-12} -> http://localhost:{1}   (estatico, {2})" -f $Tool.Name, $Tool.Port, $Tool.Dist) -ForegroundColor Green
    } else {
        Write-Host ("  [x] {0,-12} no respondio en :{1}  (ver _run\{2}.log.err)" -f $Tool.Name, $Tool.Port, $Tool.Folder) -ForegroundColor Red
    }
}

# "Deja en linea": sirve el dist ya compilado si existe (arranque instantaneo) y, si falta,
# recurre al servidor de desarrollo de la herramienta. Nunca reinicia un puerto ya activo.
function Start-Serve {
    param($Tool, [string]$Cargo, [string]$Trunk, [string]$Php)
    if (Test-Port -Port $Tool.Port) {
        Write-Host ("  [=] {0,-12} -> http://localhost:{1}   (ya en linea)" -f $Tool.Name, $Tool.Port) -ForegroundColor DarkGreen
        return
    }
    $dist = Join-Path $Root $Tool.Dist
    if ($Php -and (Test-Path (Join-Path $dist 'index.html'))) {
        Start-Static -Tool $Tool -Php $Php
    }
    else {
        Start-Tool -Tool $Tool -Cargo $Cargo -Trunk $Trunk
    }
}

Write-Head
$Cargo = Get-Cargo
$Trunk = Get-Trunk
$Php   = Get-Php

switch ($Mode) {

    'stop' {
        Write-Host '  Deteniendo servicios en los puertos 8081-8087...' -ForegroundColor Gray
        $ports = $Tools | ForEach-Object { $_.Port }
        $conns = Get-NetTCPConnection -State Listen -ErrorAction SilentlyContinue | Where-Object { $ports -contains $_.LocalPort }
        if (-not $conns) { Write-Host '  [i] No habia nada escuchando en esos puertos.' -ForegroundColor DarkGray }
        else {
            foreach ($c in $conns) {
                try {
                    $p = Get-Process -Id $c.OwningProcess -ErrorAction SilentlyContinue
                    Stop-Process -Id $c.OwningProcess -Force -ErrorAction SilentlyContinue
                    Write-Host ("  [x] puerto {0} (PID {1} {2}) detenido" -f $c.LocalPort, $c.OwningProcess, $p.ProcessName) -ForegroundColor Yellow
                } catch { }
            }
        }
        Remove-Item (Join-Path $RunDir 'pids.txt') -ErrorAction SilentlyContinue
    }

    'status' {
        Write-Host '  Estado de las herramientas:' -ForegroundColor Gray
        $on = 0
        foreach ($t in $Tools) {
            $up = Test-Port -Port $t.Port
            if ($up) { $on++ }
            $tag = if ($up) { 'EN LINEA' } else { 'apagado ' }
            $col = if ($up) { 'Green' } else { 'DarkGray' }
            Write-Host ("    {0,-12} :{1}  {2}   {3}  [{4}]" -f $t.Name, $t.Port, $tag, $t.Ref, $t.Runner) -ForegroundColor $col
        }
        Write-Host ''
        Write-Host "  $on de $($Tools.Count) en linea." -ForegroundColor Yellow
    }

    'build' {
        if (-not $Cargo) { Show-PrereqHelp; break }
        Write-Host "  cargo: $Cargo" -ForegroundColor DarkGray
        if ($Trunk) { Write-Host "  trunk: $Trunk" -ForegroundColor DarkGray } else { Write-Host '  trunk: (no encontrado; se saltan las apps trunk)' -ForegroundColor DarkYellow }
        Write-Host '  Compilando cada app. Puede tardar varios minutos...' -ForegroundColor Gray
        foreach ($t in $Tools) {
            Write-Host ''
            Write-Host ("  == {0} ({1}) [{2}] ==" -f $t.Name, $t.Folder, $t.Runner) -ForegroundColor Yellow
            $sw = [System.Diagnostics.Stopwatch]::StartNew()
            if ($t.Runner -eq 'trunk') {
                if (-not $Trunk) { Write-Host '     sin trunk, se salta.' -ForegroundColor Red; continue }
                $web = Join-Path $Root $t.Web
                if (-not (Test-Path $web)) { Write-Host '     falta el directorio web, se salta.' -ForegroundColor Red; continue }
                Push-Location $web
                try { & $Trunk build --release; if ($LASTEXITCODE -ne 0) { Write-Host "     fallo ($LASTEXITCODE)" -ForegroundColor Red } } finally { Pop-Location }
            }
            else {
                $repo = Join-Path $Root $t.Folder
                Push-Location $repo
                try { & $Cargo xtask web; if ($LASTEXITCODE -ne 0) { Write-Host "     fallo ($LASTEXITCODE)" -ForegroundColor Red } } finally { Pop-Location }
            }
            $sw.Stop()
            Write-Host ("     listo en {0:n1} s" -f $sw.Elapsed.TotalSeconds) -ForegroundColor Green
        }
    }

    'static' {
        if (-not $Php) {
            Write-Host '[!] No se encontro PHP. Instalalo o agregalo al PATH.' -ForegroundColor Red
            Write-Host '    (Tambien podes usar: npx serve <carpeta>)' -ForegroundColor Gray
            break
        }
        Write-Host "  php: $Php" -ForegroundColor DarkGray
        Write-Host '  Sirviendo dist (MIME wasm + cabeceras COOP/COEP via router PHP)...' -ForegroundColor Gray
        foreach ($t in $Tools) { Start-Static -Tool $t -Php $Php }
    }

    'dev' {
        if (-not $Cargo -and -not $Trunk) { Show-PrereqHelp; break }
        Write-Host "  cargo: $(if ($Cargo) { $Cargo } else { '(no encontrado)' })" -ForegroundColor DarkGray
        Write-Host '  Arrancando servidores de desarrollo (recompila; puede tardar)...' -ForegroundColor Gray
        foreach ($t in $Tools) { Start-Tool -Tool $t -Cargo $Cargo -Trunk $Trunk }
    }

    default {
        Write-Host "  cargo: $(if ($Cargo) { $Cargo } else { '(no encontrado)' })" -ForegroundColor DarkGray
        if (-not $Php) { Write-Host '  php: (no encontrado; solo se arrancara lo que el toolchain pueda compilar)' -ForegroundColor DarkYellow }
        Write-Host '  Dejando la suite en linea (8081-8087); los dist ya compilados se sirven al instante...' -ForegroundColor Gray
        foreach ($t in $Tools) { Start-Serve -Tool $t -Cargo $Cargo -Trunk $Trunk -Php $Php }
    }
}

Write-Host ''
Write-Host '  Panel CANDIL OS: ' -NoNewline -ForegroundColor DarkYellow
Write-Host 'http://localhost/candil/candil-suite/index.html' -ForegroundColor Yellow
Write-Host ''
