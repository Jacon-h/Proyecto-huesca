# Active Directory (dc1): preparación para la sincronización

Esto sustituye a la "sección 14.2" que citaban el README y `ad.sh`, que no existe. Los scripts de Linux
(`sincronizar-ad.sh`, `cambiar-clave.sh`) esperan **exactamente** esta estructura; la sección 4.5.1 del checkpoint
(`Usuarios_Sincronizados`, `svc_lsc`, LSC) describe otro diseño y no sirve para esta instalación.

## Qué tiene que existir en AD

| Objeto | DN (dominio `ad.huesca.empresa.lan`) |
|---|---|
| OU raíz | `OU=Huesca,DC=ad,DC=huesca,DC=empresa,DC=lan` |
| OU de cuentas | `OU=Investigadores,OU=Huesca,...` y `OU=Visitas,OU=Huesca,...` |
| Grupos | `CN=GG-Investigadores` y `CN=GG-Visitas`, en `OU=Grupos,OU=Huesca,...` |
| Cuenta de servicio | `CN=svc-sync,OU=Servicios,OU=Huesca,...` (sin permisos de administrador) |

Permisos de `svc-sync`: crear/eliminar usuarios y control total sobre los usuarios de Investigadores y Visitas
(incluye habilitar cuentas y restablecer contraseñas), y escribir `member` en los dos grupos. Nada más.

## Pasos

1. **En dc1**, copia `sincronizacion/windows-preparar-ad.ps1`, abre PowerShell como administrador y ejecuta:
   ```powershell
   Set-ExecutionPolicy -Scope Process Bypass
   .\windows-preparar-ad.ps1 -LongitudMinimaClave 12
   ```
   Te pide la contraseña de `svc-sync`. Es repetible. Crea OUs, grupos, cuenta y delegación, y comprueba el certificado.
2. **LDAPS**: dc1 necesita un certificado de servidor a nombre de `dc1.ad.huesca.empresa.lan` emitido por la CA
   cuyo `.cer` ya tienes. El script avisa si falta. Si hay una CA de empresa, el controlador lo solicita solo:
   `gpupdate /force` y `certutil -pulse`. Si aún no hay CA:
   ```powershell
   Install-WindowsFeature ADCS-Cert-Authority -IncludeManagementTools
   Install-AdcsCertificationAuthority -CAType EnterpriseRootCa -CACommonName "Huesca-CA" `
       -KeyLength 2048 -HashAlgorithmName SHA256 -ValidityPeriod Years -ValidityPeriodUnits 10
   certutil -ca.cert C:\huesca-ad-ca.cer      # este es el .cer que va a sincronizacion/
   ```
   Si tu CA tiene una subordinada, `huesca-ad-ca.cer` debe contener la cadena (PEM concatenado) o la raíz.
3. **En Linux**: copia `huesca-ad-ca.cer` a `sincronizacion/`, pon en `.env` la misma contraseña en
   `AD_SYNC_PASSWORD` (entre comillas simples si lleva `$ ! #`), y lanza:
   ```bash
   sudo ./instalar.sh ad
   ```

## Comprobaciones

En dc1:
```powershell
Get-ADOrganizationalUnit -Filter * -SearchBase "OU=Huesca,$((Get-ADDomain).DistinguishedName)" | Select Name
Get-ADUser svc-sync
dsacls "OU=Investigadores,OU=Huesca,$((Get-ADDomain).DistinguishedName)" | Select-String svc-sync
Test-NetConnection localhost -Port 636
```
En Linux:
```bash
openssl s_client -connect dc1.ad.huesca.empresa.lan:636 -verify_hostname dc1.ad.huesca.empresa.lan </dev/null 2>/dev/null | grep 'Verify return'
sudo DRY_RUN=1 sincronizar-ad.sh        # muestra qué haría sin tocar AD
```

## Errores típicos

| Síntoma | Causa |
|---|---|
| `Verify return code: 21/20/18` | El `.cer` no es el de la CA que emitió el certificado de dc1, o falta la cadena |
| `Verify return code: 62` (hostname mismatch) | El certificado no lleva `dc1.ad.huesca.empresa.lan` como nombre DNS |
| `no puedo entrar en AD como CN=svc-sync...` | Contraseña distinta de `AD_SYNC_PASSWORD`, o la cuenta no está en `OU=Servicios,OU=Huesca` |
| `ldapmodify falló` al crear/habilitar | Falta una delegación: repite el script de Windows |
| Cuentas creadas pero deshabilitadas | Es lo normal hasta fijar contraseña: `AD_CLAVE_INICIAL` (12+ caracteres) o `sudo cambiar-clave.sh <usuario>` |
