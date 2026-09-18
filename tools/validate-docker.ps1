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

# 6. Compose coherence. The host port is a deployment choice (this one publishes
#    8098 and is reached through the nginx proxy manager), but the container side
#    must stay 8080 because that is what nginx listens on.
$composeText = Get-Content $compose -Raw
$mountText = Get-Content $composeMount -Raw
Check ($composeText -match '"\d+:8080"') "compose principal publica el 8080 del contenedor"
Check ($mountText -match '8081:8080') "compose montado publica 8081 (no choca con el otro)"
Check ($composeText -match 'context:\s*\.') "compose principal usa el contexto actual"
Check ($mountText -match '\./nginx\.conf:/etc/nginx/nginx\.conf:ro') "compose montado monta nginx.conf de solo lectura"
Check ($mountText -match '\./:/usr/share/nginx/html:ro') "compose montado monta la carpeta como raiz web"

# 7. Standard Compose top-level shape.
Check ($composeText -match '(?m)^services:') "docker-compose.yml tiene la clave services"
Check ($mountText -match '(?m)^services:') "docker-compose.mount.yml tiene la clave services"

# 8. Cache-busting: the version rename is what stops browsers serving an old
#    release, and a half-applied rename would produce a page that 404s.
$bump = Join-Path $Root "version-bump.sh"
Check (Test-Path $bump) "existe version-bump.sh"
$bumpText = Get-Content $bump -Raw
$dockerText2 = Get-Content $dockerfile -Raw
Check ($dockerText2 -match 'ARG\s+VERSION=') "el Dockerfile declara ARG VERSION"
Check ($dockerText2 -match 'version-bump\.sh\s+"\$VERSION"') "el Dockerfile ejecuta el renombrado con la version"
Check ($bumpText -match 'index-\$VERSION\.js') "el renombrado cubre el loader (.js)"
Check ($bumpText -match 'index-\$VERSION\.wasm') "el renombrado cubre el motor (.wasm)"
Check ($bumpText -match 'index-\$VERSION\.pck') "el renombrado cubre el paquete del juego (.pck)"
Check ($bumpText -match 'worklet') "el renombrado cubre los worklets de audio (derivan del mismo nombre base)"
# The sed replacement spans two lines in the script (shell line continuation),
# so this looks for the one line that carries the executable rewrite rather than
# trying to match the whole shape with one regex.
$executableLine = Select-String -Path $bump -Pattern 'executable' |
    Where-Object { $_.Line -match '\$VERSION' -and $_.Line -match 's\|' } |
    Select-Object -First 1
Check ($null -ne $executableLine) "el renombrado actualiza executable, de donde el motor saca los nombres"
Check ($dockerText2 -match 'gzip -9 .*index-\$VERSION\.wasm') "el Dockerfile comprime el wasm en el build"
Check ($conf -match 'gzip_static\s+on;') "nginx sirve la copia comprimida (gzip_static)"

# 9. Caching rules: the versioned payload is immutable, the entry point is not.
Check ($conf -match 'location = /index\.html') "el index.html tiene su propia regla"
Check ($conf -match 'location = /index\.html\s*\{[^}]*no-cache') "el index.html nunca se cachea"
Check ($conf -match 'immutable') "los archivos versionados se cachean fuerte"
$versionedBlock = [regex]::Match($conf, '(?s)location ~\* -\[0-9\].*?\}')
Check ($versionedBlock.Success -and $versionedBlock.Value -match 'immutable') "la regla de los versionados usa immutable"

Write-Output ""
if ($failures -eq 0) { Write-Output "VALIDACION: TODO OK" } else { Write-Output "VALIDACION: $failures FALLAS" }
exit $failures
