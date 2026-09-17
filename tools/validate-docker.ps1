# Static validation of the Docker files in build/web, for machines without a
# Docker daemon (here: Docker Desktop is not installed). It checks the things
# that would actually break a `docker build` or make the game fail to load:
#   * every COPY source in the Dockerfile exists in the build folder
#   * every build artifact is copied into the image (nothing silently missing)
#   * nginx serves from the same directory the files are copied to
#   * the MIME types Godot needs are declared
#   * the compose services agree on ports and file references
param(
    [string]$Root = "E:\software\juegos\mataCudos\build\web"
)

$failures = 0
function Check($condition, $message) {
    if ($condition) { Write-Output "  OK    $message" }
    else { Write-Output "  FALLA $message"; $script:failures++ }
}

$dockerfile = Join-Path $Root "Dockerfile"
$nginxConf = Join-Path $Root "nginx.conf"
$compose = Join-Path $Root "docker-compose.yml"
$composeMount = Join-Path $Root "docker-compose.mount.yml"

Check (Test-Path $dockerfile) "existe Dockerfile"
Check (Test-Path $nginxConf) "existe nginx.conf"
Check (Test-Path $compose) "existe docker-compose.yml"
Check (Test-Path $composeMount) "existe docker-compose.mount.yml"

# 1. COPY sources must exist.
$copies = Select-String -Path $dockerfile -Pattern '^COPY\s+(\S+)\s+' | ForEach-Object { $_.Matches[0].Groups[1].Value }
Check ($copies.Count -gt 0) "el Dockerfile tiene instrucciones COPY ($($copies.Count))"
foreach ($source in $copies) {
    if ($source -eq "nginx.conf") {
        Check (Test-Path $nginxConf) "COPY $source -> existe"
    } else {
        Check (Test-Path (Join-Path $Root $source)) "COPY $source -> existe"
    }
}

# 2. Every artifact in the folder must be served: a missing COPY means the
#    container starts but the browser gets 404s.
$artifacts = Get-ChildItem $Root -File | Where-Object {
    $_.Name -match '^(index\.|.*\.worklet\.js$)' -and
    $_.Name -notmatch '\.import$'
} | Select-Object -ExpandProperty Name
$missing = @()
foreach ($artifact in $artifacts) {
    if ($copies -notcontains $artifact) { $missing += $artifact }
}
Check ($missing.Count -eq 0) "todos los archivos del build se copian$(if ($missing.Count) { " (faltan: $($missing -join ', '))" })"

# 3. nginx root must match the copy destination and the exposed port.
# EXPOSE is indented because it continues the previous line with a backslash,
# so the match must tolerate leading whitespace.
$dockerText = Get-Content $dockerfile -Raw
$conf = Get-Content $nginxConf -Raw
Check ($conf -match 'root\s+/usr/share/nginx/html;') "nginx sirve desde /usr/share/nginx/html"
Check ($conf -match 'listen\s+8080;') "nginx escucha en 8080"
Check ($dockerText -match '(?m)^\s*EXPOSE\s+8080\s*$') "el Dockerfile expone 8080"
# The web root is the destination the artifacts are copied into; take it from an
# index.html COPY so nginx.conf's own destination is not picked up.
$destination = (Select-String -Path $dockerfile -Pattern '^COPY\s+index\.html\s+(\S+)' | Select-Object -First 1).Matches[0].Groups[1].Value
Check ($destination -and $conf -match [regex]::Escape($destination.TrimEnd('/'))) "el destino del COPY coincide con la raiz de nginx ($destination)"

# 4. MIME types without which the game hangs on the loading screen.
Check ($conf -match 'application/wasm\s+wasm;') "declara application/wasm para .wasm"
Check ($conf -match 'application/octet-stream\s+pck;') "declara application/octet-stream para .pck"

# 5. The single-threaded build must NOT be served with cross-origin isolation.
Check ($conf -notmatch 'Cross-Origin-(Opener|Embedder)-Policy') "no impone cabeceras COOP/COEP (build sin hilos)"

# 6. Compose coherence.
$composeText = Get-Content $compose -Raw
$mountText = Get-Content $composeMount -Raw
Check ($composeText -match '8080:8080') "compose principal publica 8080"
Check ($mountText -match '8081:8080') "compose montado publica 8081 (no choca con el otro)"
Check ($composeText -match 'context:\s*\.') "compose principal usa el contexto actual"
Check ($mountText -match '\./nginx\.conf:/etc/nginx/nginx\.conf:ro') "compose montado monta nginx.conf de solo lectura"
Check ($mountText -match '\./:/usr/share/nginx/html:ro') "compose montado monta la carpeta como raiz web"

# 7. Standard Compose top-level shape.
Check ($composeText -match '(?m)^services:') "docker-compose.yml tiene la clave services"
Check ($mountText -match '(?m)^services:') "docker-compose.mount.yml tiene la clave services"

Write-Output ""
if ($failures -eq 0) { Write-Output "VALIDACION: TODO OK" } else { Write-Output "VALIDACION: $failures FALLAS" }
exit $failures
