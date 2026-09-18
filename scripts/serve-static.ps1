[CmdletBinding()]
param([Parameter(Mandatory)][string]$Root,[int]$Port=5173)
$ErrorActionPreference='Stop'
$Root=(Resolve-Path $Root).Path.TrimEnd('\')+'\'
$l=[Net.HttpListener]::new()
$l.Prefixes.Add("http://127.0.0.1:$Port/")
$l.Start()
$mime=@{'.html'='text/html; charset=utf-8';'.js'='text/javascript; charset=utf-8';'.css'='text/css; charset=utf-8';'.json'='application/json; charset=utf-8';'.webmanifest'='application/manifest+json; charset=utf-8';'.svg'='image/svg+xml'}
try{
 while($l.IsListening){
  $c=$l.GetContext()
  try{
   $rel=[Uri]::UnescapeDataString($c.Request.Url.AbsolutePath.TrimStart('/'));if(!$rel){$rel='index.html'}
   if($rel -match '(^|[\\/])\.\.([\\/]|$)'){throw [UnauthorizedAccessException]::new()}
   $full=[IO.Path]::GetFullPath((Join-Path $Root ($rel -replace '/', '\')))
   if(!$full.StartsWith($Root,[StringComparison]::OrdinalIgnoreCase)){throw [UnauthorizedAccessException]::new()}
   if(!(Test-Path $full -PathType Leaf)){$c.Response.StatusCode=404;$b=[Text.Encoding]::UTF8.GetBytes('Not found')}
   else{$b=[IO.File]::ReadAllBytes($full);$c.Response.ContentType=$mime[[IO.Path]::GetExtension($full)];if(!$c.Response.ContentType){$c.Response.ContentType='application/octet-stream'}}
   $c.Response.Headers['X-Content-Type-Options']='nosniff';$c.Response.Headers['Referrer-Policy']='no-referrer';$c.Response.ContentLength64=$b.Length;$c.Response.OutputStream.Write($b,0,$b.Length)
  }finally{$c.Response.Close()}
 }
}finally{$l.Stop();$l.Close()}
