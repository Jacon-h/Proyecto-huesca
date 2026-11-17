<#
 windows-preparar-ad.ps1 · Prepara Active Directory en dc1 para la sincronización desde OpenLDAP.
 Ejecutar en dc1, en PowerShell COMO ADMINISTRADOR, con una cuenta de Admins. del dominio:
     .\windows-preparar-ad.ps1
 Es repetible: lo que ya existe se deja como está.

 Crea (todo bajo el dominio detectado, p. ej. DC=ad,DC=huesca,DC=empresa,DC=lan):
   OU=Huesca
     OU=Investigadores   (aquí crea y modifica cuentas el script de Linux)
     OU=Visitas
     OU=Grupos           (GG-Investigadores y GG-Visitas)
     OU=Servicios        (cuenta svc-sync)
 y delega en svc-sync SOLO lo que necesita sobre Investigadores, Visitas y los dos grupos.
 Al final comprueba que dc1 tiene un certificado válido para LDAPS (636).
#>
#Requires -RunAsAdministrator
#Requires -Modules ActiveDirectory
param(
    [string]$OUPadre    = 'Huesca',
    [string]$CuentaSync = 'svc-sync',
    [int]$LongitudMinimaClave = 0     # p. ej. -LongitudMinimaClave 12 para fijarla en la política del dominio
)
$ErrorActionPreference = 'Stop'
Import-Module ActiveDirectory

$dom  = Get-ADDomain
$base = $dom.DistinguishedName
$nb   = $dom.NetBIOSName
$raiz = "OU=$OUPadre,$base"
Write-Host "Dominio: $($dom.DNSRoot)   Base: $base   NetBIOS: $nb" -ForegroundColor Cyan

function Asegurar-OU([string]$nombre, [string]$ruta) {
    $dn = "OU=$nombre,$ruta"
    if (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$dn'" -ErrorAction SilentlyContinue) {
        Write-Host "  OU ya existe : $dn"
    } else {
        New-ADOrganizationalUnit -Name $nombre -Path $ruta -ProtectedFromAccidentalDeletion $true
        Write-Host "  OU creada    : $dn" -ForegroundColor Green
    }
}
function Asegurar-Grupo([string]$nombre, [string]$ruta) {
    if (Get-ADGroup -Filter "SamAccountName -eq '$nombre'" -ErrorAction SilentlyContinue) {
        Write-Host "  Grupo ya existe: $nombre"
    } else {
        New-ADGroup -Name $nombre -SamAccountName $nombre -GroupScope Global -GroupCategory Security -Path $ruta
        Write-Host "  Grupo creado   : $nombre" -ForegroundColor Green
    }
}
function Ejecutar-Dsacls([string[]]$argumentos) {
    $salida = & dsacls.exe @argumentos 2>&1
    if ($LASTEXITCODE -ne 0) { throw "dsacls falló ($($argumentos -join ' ')):`n$salida" }
}

# 1. Unidades organizativas
Write-Host "`n[1/5] Unidades organizativas"
if (-not (Get-ADOrganizationalUnit -Filter "DistinguishedName -eq '$raiz'" -ErrorAction SilentlyContinue)) {
    New-ADOrganizationalUnit -Name $OUPadre -Path $base -ProtectedFromAccidentalDeletion $true
    Write-Host "  OU creada    : $raiz" -ForegroundColor Green
} else { Write-Host "  OU ya existe : $raiz" }
foreach ($ou in 'Investigadores','Visitas','Grupos','Servicios') { Asegurar-OU $ou $raiz }

# 2. Grupos
Write-Host "`n[2/5] Grupos"
foreach ($g in 'GG-Investigadores','GG-Visitas') { Asegurar-Grupo $g "OU=Grupos,$raiz" }

# 3. Cuenta de servicio
Write-Host "`n[3/5] Cuenta de servicio $CuentaSync"
if (Get-ADUser -Filter "SamAccountName -eq '$CuentaSync'" -SearchBase $base -ErrorAction SilentlyContinue) {
    Write-Host "  Ya existe. Si cambias su contraseña, pon la misma en AD_SYNC_PASSWORD (.env) y repite: sudo ./instalar.sh ad"
} else {
    $pw = Read-Host "Contraseña de $CuentaSync (12+ caracteres, compleja; será AD_SYNC_PASSWORD en .env)" -AsSecureString
    New-ADUser -Name $CuentaSync -SamAccountName $CuentaSync `
        -UserPrincipalName "$CuentaSync@$($dom.DNSRoot)" -Path "OU=Servicios,$raiz" `
        -AccountPassword $pw -Enabled $true -PasswordNeverExpires $true -CannotChangePassword $true `
        -Description 'Sincronización OpenLDAP -> AD (Linux). No es administradora.'
    Write-Host "  Cuenta creada: CN=$CuentaSync,OU=Servicios,$raiz" -ForegroundColor Green
}

# 4. Delegación (mínimo privilegio; svc-sync NO entra en ningún grupo de administradores)
Write-Host "`n[4/5] Delegación de permisos a $nb\$CuentaSync"
$cta = "${nb}\${CuentaSync}"
foreach ($ou in 'Investigadores','Visitas') {
    $dn = "OU=$ou,$raiz"
    # Crear y eliminar cuentas de usuario en la OU
    Ejecutar-Dsacls @($dn, '/I:T', '/G', "${cta}:CCDC;user")
    # Control total sobre los objetos usuario de la OU (leer/escribir atributos, restablecer contraseña, habilitar)
    Ejecutar-Dsacls @($dn, '/I:S', '/G', "${cta}:GA;;user")
    Write-Host "  Delegado en $dn"
}
foreach ($g in 'GG-Investigadores','GG-Visitas') {
    $dn = "CN=$g,OU=Grupos,$raiz"
    # Escribir solo la pertenencia (atributo member)
    Ejecutar-Dsacls @($dn, '/G', "${cta}:WP;member")
    Write-Host "  Delegado en $dn (member)"
}

# 5. Directiva de contraseñas (opcional) y comprobación de LDAPS
Write-Host "`n[5/5] Directiva y LDAPS"
if ($LongitudMinimaClave -gt 0) {
    Set-ADDefaultDomainPasswordPolicy -Identity $dom.DNSRoot -MinPasswordLength $LongitudMinimaClave
    Write-Host "  Longitud mínima de contraseña del dominio: $LongitudMinimaClave"
} else {
    $pol = Get-ADDefaultDomainPasswordPolicy
    Write-Host "  Longitud mínima actual: $($pol.MinPasswordLength) (usa -LongitudMinimaClave 12 para alinearla con OpenLDAP)"
}
$fqdn = ([System.Net.Dns]::GetHostByName($env:COMPUTERNAME)).HostName
$certs = Get-ChildItem Cert:\LocalMachine\My | Where-Object {
    $_.NotAfter -gt (Get-Date) -and
    ($_.EnhancedKeyUsageList.FriendlyName -contains 'Server Authentication') -and
    ($_.DnsNameList.Unicode -contains $fqdn)
}
if ($certs) {
    Write-Host "  OK: certificado para LDAPS a nombre de $fqdn (caduca $($certs[0].NotAfter.ToString('yyyy-MM-dd')), emisor: $($certs[0].Issuer))" -ForegroundColor Green
} else {
    Write-Host "  FALTA certificado de servidor para $fqdn en este equipo." -ForegroundColor Yellow
    Write-Host "  Con una CA de empresa instalada: gpupdate /force ; certutil -pulse   (y repite este script)."
    Write-Host "  Sin CA todavía: mira docs/ad-windows.md, sección 'LDAPS'."
}
Write-Host "`nListo. En Linux: pon AD_SYNC_PASSWORD en .env, copia huesca-ad-ca.cer a sincronizacion/ y ejecuta: sudo ./instalar.sh ad" -ForegroundColor Cyan
