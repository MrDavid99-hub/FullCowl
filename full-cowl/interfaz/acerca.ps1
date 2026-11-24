# Ficha 37: ventana «Acerca de Full Cowl». Se abre desde la tarjeta de Ajustes, pulsando la versión del menú o con F1.
# Solo enseña lo que la aplicación ya sabe: no busca nada en Internet al abrirse. Lo que no aplica, no sale.

function Abrir-Web([string]$url) {
    # Solo direcciones https:// que salen de Url-RepoPublico (nunca algo escrito por el usuario)
    if ($url -notmatch '^https://github\.com/') { return }
    try { Start-Process -FilePath $url } catch { Error-Amable 'No he podido abrir el navegador.' "Abre a mano: $url" $_.Exception.Message }
}

function Pintar-InsigniaAcerca($acdE) {
    # «Estás al día» (verde) o «Hay una versión nueva» (aviso); si todavía no se ha buscado, no sale
    try {
        $acdEst = Estado-Actualizacion
        if ($acdEst.Hay) { Poner-Insignia $acdE.AcInsignia $acdE.AcInsigniaTxt 'Hay una versión nueva' 'T_avisoFondo' 'T_aviso' }
        elseif ($acdEst.Insignia) { Poner-Insignia $acdE.AcInsignia $acdE.AcInsigniaTxt 'Estás al día' 'T_encendidaFondo' 'T_encendida' }
        else { $acdE.AcInsignia.Visibility = 'Collapsed' }
    } catch { $acdE.AcInsignia.Visibility = 'Collapsed' }
}

function Mostrar-Acerca {
    if ($script:acercaAbierta) { return }
    $acdE = Nuevo-Dialogo 'dialogo-acerca.xaml' 'Acerca de Full Cowl' '' 560
    $script:acercaAbierta = $true
    $acdRaiz = Split-Path $dirFc
    # Cabecera: logo y rótulo del tema que toca (titulo.png en oscuro, como el menú; titulo-claro.png en claro)
    try { $acdE.AcLogo.Source = Imagen (Join-Path $dirFc 'recursos\logo.png') } catch {}
    try {
        $acdTit = $(if ((Tema-Efectivo) -eq 'oscuro') { 'titulo.png' } else { 'titulo-claro.png' })
        $acdE.AcTitulo.Source = Imagen (Join-Path $dirFc "recursos\$acdTit")
    } catch {}
    # Versión (si no se puede leer, la línea no sale) e insignia de estado
    $acdVer = ''
    try { $acdVer = Version-Instalada } catch {}
    if ($acdVer) { $acdE.AcVersion.Text = "Versión $acdVer" } else { $acdE.AcVersion.Visibility = 'Collapsed' }
    Pintar-InsigniaAcerca $acdE
    # Filas
    $acdE.AcAutor.Text = Autor-FullCowl
    $acdLic = Join-Path $acdRaiz 'LICENSE'
    $acdNot = Join-Path $acdRaiz 'NOTICE.md'
    $acdHayLic = Test-Path -LiteralPath $acdLic
    $acdHayNot = Test-Path -LiteralPath $acdNot
    if ($acdHayLic) { $acdE.AcLicenciaRot.Visibility = 'Visible'; $acdE.AcLicencia.Visibility = 'Visible' }
    $acdE.AcMarcas.Text = Aviso-Marcas
    # Enlaces
    $acdE.BtnAcNovedades.Add_Click({ Abrir-Documento (Join-Path (Split-Path $dirFc) 'CHANGELOG.md') 'las novedades (CHANGELOG.md)' })
    $acdE.BtnAcManual.Add_Click({ Abrir-Documento (Join-Path (Split-Path $dirFc) 'docs\MANUAL.md') 'el manual' })
    if ($acdHayLic -or $acdHayNot) {
        $acdE.BtnAcLicencia.Visibility = 'Visible'
        if ($acdHayLic -and $acdHayNot) {
            # Los dos: un pequeño menú para elegir
            $acdMenu = New-Object System.Windows.Controls.ContextMenu
            foreach ($acdPar in @(@('Licencia (LICENSE)', 'LICENSE', 'la licencia'), @('Avisos (NOTICE.md)', 'NOTICE.md', 'los avisos'))) {
                $acdItem = New-Object System.Windows.Controls.MenuItem
                $acdItem.Header = $acdPar[0]; $acdItem.Tag = @($acdPar[1], $acdPar[2])
                $acdItem.Add_Click({ param($o, $a) Abrir-Documento (Join-Path (Split-Path $dirFc) ([string]$o.Tag[0])) ([string]$o.Tag[1]) })
                [void]$acdMenu.Items.Add($acdItem)
            }
            $acdE.BtnAcLicencia.ContextMenu = $acdMenu
            $acdE.BtnAcLicencia.Add_Click({ param($o, $a) $o.ContextMenu.PlacementTarget = $o; $o.ContextMenu.Placement = 'Bottom'; $o.ContextMenu.IsOpen = $true })
        } elseif ($acdHayLic) {
            $acdE.BtnAcLicencia.Add_Click({ Abrir-Documento (Join-Path (Split-Path $dirFc) 'LICENSE') 'la licencia' })
        } else {
            $acdE.BtnAcLicencia.Add_Click({ Abrir-Documento (Join-Path (Split-Path $dirFc) 'NOTICE.md') 'los avisos' })
        }
    }
    $acdUrl = Url-RepoPublico
    if ($acdUrl) {
        $acdE.BtnAcGithub.Visibility = 'Visible'
        $acdE.BtnAcProblema.Visibility = 'Visible'
        $acdE.BtnAcGithub.Add_Click({ Abrir-Web (Url-RepoPublico) })
        $acdE.BtnAcProblema.Add_Click({ Abrir-Web "$(Url-RepoPublico)/issues" })
    }
    # Pie
    $acdE.BtnAcBuscar.Add_Click({ Buscar-Actualizacion $true })
    $acdE.BtnAcCopiar.Add_Click({
        param($o, $a)
        try { Set-Clipboard -Value (Texto-InfoEquipo); $o.Content = 'Copiado' }
        catch { Error-Amable 'No he podido copiar la información.' 'Vuelve a intentarlo en unos segundos.' $_.Exception.Message }
    })
    $acdE.BtnAcCerrar.Add_Click({ param($o, $a) [System.Windows.Window]::GetWindow($o).Close() })
    # La insignia se refresca sola si se busca una actualización con la ventana abierta
    $acdReloj = New-Object System.Windows.Threading.DispatcherTimer
    $acdReloj.Interval = [TimeSpan]::FromSeconds(1)
    $acdReloj.Tag = $acdE
    $acdReloj.Add_Tick({ param($o, $a) Pintar-InsigniaAcerca $o.Tag })
    $acdReloj.Start()
    $acdE.Ventana.Add_Loaded({ param($o, $a) try { [void]$o.FindName('BtnAcCerrar').Focus() } catch {} })
    try { [void]$acdE.Ventana.ShowDialog() } finally { $acdReloj.Stop(); $script:acercaAbierta = $false }
}

# Tarjeta de Ajustes (resumen fijo: versión y autor)
try {
    $acdVerT = Version-Instalada
    $ResAcerca.Text = $(if ($acdVerT) { "Versión $acdVerT · creada por $(Autor-FullCowl)" } else { "Creada por $(Autor-FullCowl)" })
} catch {}
$TarjAcerca.Add_Click({ Mostrar-Acerca })
# Pulsar la versión del menú (la cabecera no cambia: solo cursor de mano y una pista)
$TxtVersion.Cursor = [System.Windows.Input.Cursors]::Hand
$TxtVersion.ToolTip = 'Acerca de Full Cowl'
$TxtVersion.Add_MouseLeftButtonUp({ param($o, $a) $a.Handled = $true; Mostrar-Acerca })
