# Abre a app em TRÊS portas, para testar os três papéis ao mesmo tempo.
#
# Porque é que isto funciona: o Firebase Auth na web guarda a sessão em
# IndexedDB, e o IndexedDB é isolado por ORIGEM (esquema + host + porta).
# `localhost:5100` e `localhost:5200` são origens diferentes para o
# browser, logo sessões diferentes — três separadores da MESMA janela do
# Chrome, cada um com o seu utilizador.
#
# A alternativa habitual (perfis do Chrome, janelas anónimas) obriga a
# saltar entre janelas e as anónimas partilham sessão entre si.
#
# Serve o build estático, por isso NÃO tem hot reload: para ver
# alterações ao código é preciso voltar a correr `flutter build web`.
# Para desenvolver com hot reload continua a usar-se `flutter run`.

param(
    [switch]$SkipBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 5001 é o emulador de Functions e 5000 costuma ser o Hosting — daí 51xx.
$ports = @(5100, 5200, 5300)
$labels = @('GESTOR', 'INSTRUTOR', 'ALUNA')

if (-not $SkipBuild) {
    Write-Host "A compilar a app (aponta para os emuladores)..." -ForegroundColor Cyan
    flutter build web -t lib/main_development.dart
    if ($LASTEXITCODE -ne 0) { throw "O build falhou." }
}

if (-not (Test-Path 'build/web/index.html')) {
    throw "Não existe build/web. Corre sem -SkipBuild."
}

Write-Host ""
Write-Host "A servir em tres portas..." -ForegroundColor Cyan

$jobs = @()
foreach ($port in $ports) {
    $jobs += Start-Job -ScriptBlock {
        param($dir, $p)
        Set-Location $dir
        python -m http.server $p --directory build/web
    } -ArgumentList $root, $port
}

Start-Sleep -Seconds 2

Write-Host ""
Write-Host "Contas de teste:" -ForegroundColor Green
Write-Host "  http://localhost:5100  ->  GESTOR      leo@nxtperformancestudio.pt / DevPass123!"
Write-Host "  http://localhost:5200  ->  INSTRUTOR   ana@nxtperformancestudio.pt / InstructorPass123!"
Write-Host "  http://localhost:5300  ->  ALUNA       000001 / MemberPass123!"
Write-Host ""
Write-Host "(Staff entra com email; alunos com o no de socio - mesmo campo.)"
Write-Host ""
Write-Host "Ctrl+C para parar os tres servidores." -ForegroundColor Yellow

foreach ($i in 0..2) {
    Start-Process "http://localhost:$($ports[$i])"
    Start-Sleep -Milliseconds 400
}

try {
    while ($true) { Start-Sleep -Seconds 1 }
}
finally {
    Write-Host ""
    Write-Host "A parar os servidores..." -ForegroundColor Cyan
    $jobs | Stop-Job -ErrorAction SilentlyContinue
    $jobs | Remove-Job -Force -ErrorAction SilentlyContinue
}
