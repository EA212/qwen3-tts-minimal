$ErrorActionPreference = 'Stop'
$dir = Join-Path $PSScriptRoot 'models'
New-Item -ItemType Directory -Force -Path $dir | Out-Null

$base = 'https://www.modelscope.cn/models/tardigrade4ai/Qwen3-TTS-GGUF/resolve/master/'
$items = @(
    @{ Name = 'qwen-talker-0.6b-customvoice-Q4_K_M.gguf';
       Size = 604878080;
       Sha  = 'b3a7e6613d80f8a703c06267fc1e94d48ce91932ab82ab6e31c50f4ca4868e1e' },
    @{ Name = 'qwen-tokenizer-12hz-Q4_K_M.gguf';
       Size = 254974752;
       Sha  = 'cf3788b4d50aaa665fb6e57c170396aae03a3555fea52d2b5d0cda902d658039' }
)

$curl = Get-Command curl.exe -ErrorAction SilentlyContinue

foreach ($it in $items) {
    $dst = Join-Path $dir $it.Name
    if ((Test-Path $dst) -and ((Get-Item $dst).Length -eq $it.Size)) {
        Write-Host ("[skip] {0} already present" -f $it.Name)
        continue
    }
    Write-Host ("[download] {0}  ({1:N0} bytes)" -f $it.Name, $it.Size)
    $url = $base + $it.Name
    if ($curl) {
        & curl.exe -L --fail --retry 3 --retry-delay 2 -o $dst $url
        if ($LASTEXITCODE -ne 0) { throw ("download failed: " + $it.Name) }
    } else {
        Invoke-WebRequest -Uri $url -OutFile $dst -UseBasicParsing
    }
    $len = (Get-Item $dst).Length
    if ($len -ne $it.Size) { throw ("wrong size: {0} got {1}" -f $it.Name, $len) }
    $hash = (Get-FileHash -Algorithm SHA256 $dst).Hash.ToLower()
    if ($hash -ne $it.Sha) { throw ("SHA256 mismatch: {0}" -f $it.Name) }
    Write-Host ("[ok] {0}  SHA256 verified" -f $it.Name)
}
Write-Host ''
Write-Host 'Models ready. Now double-click start.bat'
