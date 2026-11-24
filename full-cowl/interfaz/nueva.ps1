# =====================================================================
#  Interfaz nueva: página «Nueva máquina»
#  Antes era una pestaña de la ventana de siempre (gui.ps1, quitada en la 2.0): recoge
#  lo elegido y lanza nueva-maquina.ps1 en una consola aparte.
# =====================================================================

$script:bases = @()
$script:clones = @()
$script:red = $null
$script:hostEditado = $false
$script:rellenandoHost = $false
$script:selExtrasNueva = $null; $script:tipoExtrasNueva = ''
$script:tamBasesNueva = @{}
$script:nuevaResAbajo = $false
$script:cacheComprobNueva = @{ Hora = [datetime]::MinValue; Vmware = $false; Pass = $false }
$listaUbu = @(Lista-SoftwareUbuntu)

function Base-Actual {
    $i = $NuevaBase.SelectedIndex
    if ($i -ge 0 -and $i -lt $script:bases.Count) { return $script:bases[$i] }
    return $null
}
function Dominios-Conocidos { return @($script:clones | Where-Object { $_.Dominio -and $_.IP }) }

function Actualizar-RedNueva {
    $b = Base-Actual
    $activa = [bool]$NuevaIpFija.IsChecked -and $b -and $b.ConAgente
    foreach ($ctl in $NuevaIp, $NuevaPrefijo, $NuevaGw, $NuevaDns) { $ctl.IsEnabled = $activa }
    $usadas = @($script:clones | Where-Object { $_.IP } | ForEach-Object { $_.IP })
    $NuevaRedNota.Text = "Red NAT $($script:red.Subred)/$($script:red.Prefijo) · DHCP desde .128" + $(if ($usadas.Count) { " · ya usadas: $($usadas -join ', ')" } else { '' })
}

function Proponer-RedNueva {
    $modo = $NuevaAd.SelectedIndex
    $usadas = @($script:clones | Where-Object { $_.IP } | ForEach-Object { $_.IP })
    $desde = if ($modo -eq 1) { 10 } else { 20 }
    $NuevaIp.Text = Proponer-IP $script:red $usadas $desde
    $NuevaPrefijo.Text = [string]$script:red.Prefijo
    $NuevaGw.Text = $script:red.Puerta
    $NuevaDns.Text = $(if ($modo -eq 2 -and $NuevaDcIp.Text) { $NuevaDcIp.Text } else { $script:red.Puerta })
}

function Actualizar-AdNueva {
    $modo = $NuevaAd.SelectedIndex   # 0 nada, 1 crear dominio, 2 unir
    $NuevaAdCampos.Visibility = $(if ($modo -gt 0) { 'Visible' } else { 'Collapsed' })
    $NuevaDcCaja.Visibility = $(if ($modo -eq 2) { 'Visible' } else { 'Collapsed' })
    # Un controlador de dominio ya instala AD DS y DNS: salen marcados y fijos en los extras (ficha 20)
    if ($script:selExtrasNueva) {
        try { Bloquear-ExtrasSelector $script:selExtrasNueva $(if ($modo -eq 1) { @{ dns = 'Ya lo instala Active Directory'; adds = 'Ya lo instala Active Directory' } } else { @{} }) } catch { Escribir-Log ("Extras (dominio): " + $_.Exception.Message) }
    }
    if ($modo -eq 1) {
        $NuevaIpFija.IsChecked = $true; $NuevaIpFija.IsEnabled = $false
        $NuevaDcIp.Text = ''
        $NuevaAdNota.Text = 'Instala AD DS + DNS y crea el dominio. Necesita IP fija. Tarda unos 10-15 minutos.'
        if (-not $NuevaIp.Text) { Proponer-RedNueva }
    } else {
        $NuevaIpFija.IsEnabled = $true
        $NuevaAdNota.Text = $(if ($modo -eq 2) { 'Se une con tu usuario de las VMs (o el administrador). Enciende antes el controlador.' } else { '' })
    }
    # Dominios que ya tienes: un botón para cada uno rellena dominio, NetBIOS e IP del controlador
    $NuevaDominiosConocidos.Children.Clear()
    if ($modo -eq 2) {
        foreach ($d in @(Dominios-Conocidos)) {
            $btn = New-Object System.Windows.Controls.Button
            $btn.Style = [System.Windows.Application]::Current.FindResource('BotonSecundario')
            $btn.Content = "$($d.Dominio)  ·  $($d.IP)"
            $btn.Tag = Glifo 0xE774
            $btn.Height = 28; $btn.Padding = New-Object System.Windows.Thickness(10, 0, 10, 0)
            $btn.Margin = New-Object System.Windows.Thickness(0, 0, 6, 6)
            $btn.DataContext = [string]$d.Dominio
            $btn.Add_Click({ param($s, $a) $NuevaDominio.Text = $s.DataContext })
            [void]$NuevaDominiosConocidos.Children.Add($btn)
        }
    }
    Actualizar-RedNueva
}

function Actualizar-NotaExtrasNueva {
    $b = Base-Actual
    if (-not $b) { $NuevaExtrasNota.Text = ''; return }
    if (-not $b.ConAgente -or $NuevaExtrasAbierto.Visibility -ne 'Visible') { $NuevaExtrasNota.Text = ''; return }
    if ($b.EsWindows) {
        $marcadas = @(Marcados-SelectorExtras $script:selExtrasNueva)
        $n = 'Se instalan solos en el primer arranque (Windows puede reiniciarse). Cómo va cada uno sale en el panel de la máquina, en Mis máquinas.'
        if (@($marcadas | Where-Object { $ExtrasAnidados -contains $_ }).Count) {
            $n += "`nHyper-V, Sandbox o WSL: dale 8 GB de RAM o más. Si la máquina no arranca, desactiva Hyper-V en tu PC."
            $NuevaExtrasNota.Foreground = Pincel $Colores.Aviso
        } else { $NuevaExtrasNota.Foreground = Pincel $Colores.Suave }
        $NuevaExtrasNota.Text = $n
    } else {
        $NuevaExtrasNota.Foreground = Pincel $Colores.Suave
        $NuevaExtrasNota.Text = 'Se instalan en segundo plano en el primer arranque: puedes entrar mientras. Cómo va cada uno sale en el panel de la máquina (Mis máquinas); el registro queda dentro, en /var/log/fullcowl-extras.log'
    }
}

function Rellenar-ExtrasNueva {
    $b = Base-Actual
    # (ficha 20) El selector de extras (interfaz/extras.ps1) con el catálogo de la base elegida
    if (-not $script:selExtrasNueva) { $script:selExtrasNueva = Nuevo-SelectorExtras $NuevaExtras { Actualizar-NotaExtrasNueva; Actualizar-ResumenNueva } }
    $sel = $script:selExtrasNueva
    if (-not $b -or -not $b.ConAgente) {
        [void](Cargar-SelectorExtras $sel $null @()); $script:tipoExtrasNueva = ''
        $NuevaExtrasPlegado.Visibility = 'Collapsed'; $NuevaExtrasAbierto.Visibility = 'Collapsed'
        return
    }
    # Al cambiar entre bases del mismo tipo se conserva lo marcado; si no, lo de la última vez
    $tipoB = $(if ($b.EsWindows) { 'win' } else { 'lin' })
    $yaAbierto = ($NuevaExtrasAbierto.Visibility -eq 'Visible')
    if ($script:tipoExtrasNueva -eq $tipoB) { $marcados = @($sel.Marcados.ToArray()) }
    elseif ($b.EsWindows) { $marcados = @(Pref @('nueva', 'win', 'extras') @()) }
    else {
        $marcados = @(Pref @('nueva', 'ubu', 'software') @() | Where-Object { $_ -ne 'actualizar' })
        $NuevaActualizar.IsChecked = (@(Pref @('nueva', 'ubu', 'software') @()) -contains 'actualizar')
    }
    $mismoTipo = ($script:tipoExtrasNueva -eq $tipoB)
    $script:tipoExtrasNueva = $tipoB
    $NuevaActualizar.Visibility = $(if ($b.EsWindows) { 'Collapsed' } else { 'Visible' })
    if ($b.EsWindows) { $NuevaActualizar.IsChecked = $false }
    $quitados = @(Cargar-SelectorExtras $sel $b $marcados)
    if ($mismoTipo -and $quitados.Count) { Mostrar-Toast "Se han desmarcado $(Plural $quitados.Count 'extra que no vale' 'extras que no valen') para esta base: $((@($quitados | ForEach-Object { Nombre-Extra $_ }) -join ', '))." }
    $abrir = [bool]($yaAbierto -or $sel.Marcados.Count -or ($NuevaActualizar.IsChecked -and -not $b.EsWindows))
    $NuevaExtrasAbierto.Visibility = $(if ($abrir) { 'Visible' } else { 'Collapsed' })
    $NuevaExtrasPlegado.Visibility = $(if ($abrir) { 'Collapsed' } else { 'Visible' })
}
$BtnNuevaExtras.Add_Click({
    $NuevaExtrasAbierto.Visibility = 'Visible'; $NuevaExtrasPlegado.Visibility = 'Collapsed'
    Actualizar-NotaExtrasNueva
})
$NuevaActualizar.Add_Click({ Actualizar-ResumenNueva })

function Cambio-BaseNueva {
    $b = Base-Actual
    if (-not $b) {
        foreach ($ctl in $NuevaTarjetaAd, $NuevaTarjetaUbu, $NuevaTarjetaExtras) { $ctl.Visibility = 'Collapsed' }
        $NuevaTarjetaRed.IsEnabled = $false
        $NuevaBaseAviso.Visibility = 'Collapsed'
        $NuevaResTarjeta.Visibility = 'Collapsed'
        return
    }
    $tipo = if ($b.Familia) { $b.Familia } elseif ($b.EsWindows) { if ($b.EsServidor) { 'Windows Server' } else { 'Windows' } } else { 'Linux' }
    $NuevaBaseNota.Text = $tipo + "  ·  usuario $($b.Usuario)" + $(if ($b.ConAgente -and -not $b.ClaveTemporal) { '  ·  hecha antes de la 2.0 (lleva la contraseña dentro; rehazla para más seguridad)' } else { '' })
    $NuevaBaseAviso.Visibility = $(if ($b.ConAgente) { 'Collapsed' } else { 'Visible' })
    $NuevaBaseAvisoTxt.Text = $(if ($b.Manual) { 'Base de instalación manual: la máquina se clona tal cual (sin nombre de equipo, IP fija, dominio ni extras automáticos). Lo configuras tú dentro.' } else { 'Esta base es de una versión anterior: no admite IP fija, dominio ni extras (solo se pondrá el nombre de equipo). Rehazla en «Crear base» para tenerlos.' })
    $NuevaTarjetaAd.Visibility = $(if ($b.EsWindows) { 'Visible' } else { 'Collapsed' })
    $NuevaTarjetaUbu.Visibility = $(if ($b.EsWindows) { 'Collapsed' } else { 'Visible' })
    $NuevaTarjetaExtras.Visibility = 'Visible'
    $NuevaResTarjeta.Visibility = 'Visible'
    $NuevaTarjetaAd.IsEnabled = [bool]$b.ConAgente
    $NuevaTarjetaRed.IsEnabled = [bool]$b.ConAgente
    $NuevaSinAgente.Visibility = $(if ($b.ConAgente) { 'Collapsed' } else { 'Visible' })
    $NuevaSinAgenteTxt.Text = $(if ($b.Manual) { 'Base de instalación manual: se clona tal cual y no admite IP fija, servicios ni dominio automáticos. Lo configuras tú dentro de la máquina.' } else { 'Esta base es de una versión anterior y no admite opciones extra (IP, servicios, dominio). Rehazla en «Crear base» para tenerlas. Solo se pondrá el nombre de equipo.' })
    $NuevaExtrasTitulo.Text = 'Extras (opcional)'
    $NuevaUbuTitulo.Text = $tipo
    # Zona horaria (ficha 36): la primera opción es «la de la base» = no se toca nada (como antes)
    $zonaBase = Resolver-Zona ([string]$b.Zona)
    $filasZona = @([pscustomobject]@{ Clave = ''; Nombre = "La de la base ($($zonaBase.Corto))" }) + @(Obtener-Zonas | Where-Object { $_.Clave -ne $zonaBase.Clave })
    Llenar-ComboClave $NuevaZona $filasZona ''
    $NuevaZona.IsEnabled = [bool]$b.ConAgente
    $NuevaIdiomaNota.Text = "Idioma: $((Resolver-Idioma ([string]$b.Idioma)).Nombre) (viene de la base)" + $(if (-not $b.ConAgente) { '. Esta base no puede cambiar la zona sola: se queda la suya.' } else { '' })

    $NuevaAd.Items.Clear()
    [void]$NuevaAd.Items.Add('Nada')
    [void]$NuevaAd.Items.Add($(if ($b.EsServidor) { 'Crear un dominio nuevo (será el controlador)' } else { '(Crear un dominio: solo en Windows Server)' }))
    [void]$NuevaAd.Items.Add('Unir a un dominio existente')
    $NuevaAd.SelectedIndex = 0
    Rellenar-ExtrasNueva
    Actualizar-AdNueva
    Actualizar-NotaExtrasNueva
    Actualizar-ResumenNueva
}

# ---------------------------------------------------------------- selector de bases (tarjetas)
function Elegir-BaseNueva([string]$nombre) {
    for ($k = 0; $k -lt $script:bases.Count; $k++) {
        if ([string]$script:bases[$k].Nombre -eq $nombre) { $NuevaBase.SelectedIndex = $k; return }
    }
}

$script:baseDeClon = @{}   # vmx -> base de la que salió (no cambia: se lee del .vmx una sola vez por sesión)
function Pintar-SelectorNueva([switch]$Forzar) {
    try {
        $cuentan = @{}
        foreach ($cl in $script:clones) {
            $bn = $script:baseDeClon[[string]$cl.Vmx]
            if ($null -eq $bn) {
                $bn = ''
                try { $bn = [string](Leer-ValorVmx $cl.Vmx 'guestinfo.vmtareas.base') } catch {}
                $script:baseDeClon[[string]$cl.Vmx] = $bn
            }
            if ($bn) { $cuentan[$bn] = 1 + [int]$cuentan[$bn] }
        }
        $ops = @()
        foreach ($bs in $script:bases) {
            $sx = $null
            foreach ($cand in $sistemas) { if ([string]$cand.Clave -eq [string]$bs.Nombre) { $sx = $cand; break } }
            $partes = $(if ($sx) { Partir-NombreSistema ([string]$sx.Nombre) } else { @([string]$bs.Nombre, '') })
            $tam = [double]$script:tamBasesNueva[[string]$bs.Nombre]
            $txtTam = $(if ($tam -ge 1GB) { '{0:0} GB' -f ($tam / 1GB) } elseif ($tam -gt 0) { Formato-Tamano $tam } else { '' })
            $n = [int]$cuentan[[string]$bs.Nombre]
            $txtN = $(if ($n -eq 0) { 'sin máquinas' } else { Plural $n 'máquina' 'máquinas' })
            $filaSis = $(if ($sx) { $sx } else { [pscustomobject]@{ Clave = [string]$bs.Nombre; Tipo = $(if ($bs.EsWindows) { 'windows' } else { 'ubuntu' }) } })
            $ops += @{ Clave = [string]$bs.Nombre; Nombre = $partes[0]; Sub = $partes[1]; Sub2 = (@($txtTam, $txtN) | Where-Object { $_ }) -join ' · '
                       Grupo = (Grupo-Sistema $filaSis); Etiqueta = $(if ($bs.Manual) { 'Manual' } elseif (-not $bs.ConAgente) { 'Antigua' } else { '' }); EtiquetaAviso = $true
                       Fila = (Fila-IconoSistema $filaSis) }
        }
        $actual = $(if (Base-Actual) { [string](Base-Actual).Nombre } else { '' })
        # Si no ha cambiado nada desde la última vez (lo normal al volver a la página), no se rehacen las tarjetas: rehacerlas
        # todas es lo que más tardaba al entrar en «Nueva máquina»
        $firma = (@($ops | ForEach-Object { "$($_.Clave)|$($_.Sub2)|$($_.Etiqueta)" }) -join ';') + "#$actual"
        if (-not $Forzar -and $firma -eq $script:firmaSelNueva -and $NuevaSelector.Children.Count) { return }
        $script:firmaSelNueva = $firma
        Pintar-Selector $NuevaSelector $ops $actual { param($clave) Elegir-BaseNueva $clave } 'BaseNueva'
    } catch { Escribir-Log ("Selector de Nueva máquina: " + ($_ | Out-String)) }
}

# ---------------------------------------------------------------- resumen fijo (lado derecho)
function Actualizar-ResumenNueva {
    try {
        $b = Base-Actual
        if (-not $b) { return }
        if ($script:resNuevaClave -ne [string]$b.Nombre) {
            $script:resNuevaClave = [string]$b.Nombre
            $sx = $null
            foreach ($cand in $sistemas) { if ([string]$cand.Clave -eq [string]$b.Nombre) { $sx = $cand; break } }
            $filaSis = $(if ($sx) { $sx } else { [pscustomobject]@{ Clave = [string]$b.Nombre; Tipo = $(if ($b.EsWindows) { 'windows' } else { 'ubuntu' }) } })
            $NuevaResPastilla.Content = Pastilla-Sistema (Fila-IconoSistema $filaSis) 44
            $pn = $(if ($sx) { Partir-NombreSistema ([string]$sx.Nombre) } else { @([string]$b.Nombre, '') })
            $NuevaResNombre.Text = $pn[0]; $NuevaResSub.Text = $pn[1]
        }
        $nombre = $NuevaNombre.Text.Trim()
        $motivo = $(if ($nombre) { Validar-NombreMaquina $nombre } else { 'Falta el nombre de la máquina.' })
        $mb = Texto-AMb $NuevaRam.Text; $cpus = Numero $NuevaCpu.Text; $vram = Numero $NuevaVram.Text
        $completa = [bool]$NuevaCompleta.IsChecked
        $modoAd = $NuevaAd.SelectedIndex
        $dom = $NuevaDominio.Text.Trim()
        $red = $(if ($b.ConAgente -and $NuevaIpFija.IsChecked -and $NuevaIp.Text.Trim()) { $NuevaIp.Text.Trim() } else { 'Automática (DHCP)' })
        $dominioTxt = $(if ($b.EsWindows -and $b.ConAgente -and $modoAd -eq 1 -and $dom) { "Crea $dom" } elseif ($b.EsWindows -and $b.ConAgente -and $modoAd -eq 2 -and $dom) { "Une a $dom" } else { '—' })
        $idsExtras = @(); $catExtras = @()
        if ($b.ConAgente -and $script:selExtrasNueva) { $idsExtras = @(Marcados-SelectorExtras $script:selExtrasNueva); $catExtras = @($script:selExtrasNueva.Catalogo) }
        $nombresExtras = @($catExtras | Where-Object { $idsExtras -contains $_.Id } | ForEach-Object { [string]$_.Nombre })
        if ($b.ConAgente -and -not $b.EsWindows -and $NuevaActualizar.IsChecked) { $nombresExtras = @('Actualizar el sistema') + $nombresExtras }
        $txtExtras = $(if (-not $nombresExtras.Count) { 'Ninguno' } elseif ($nombresExtras.Count -le 3) { $nombresExtras -join ', ' } else { (@($nombresExtras | Select-Object -First 3) -join ', ') + " y $($nombresExtras.Count - 3) más" })

        $NuevaResLineas.Children.Clear()
        [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Nombre' $(if ($nombre) { $nombre } else { '—' })))
        [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Copia' $(if ($completa) { 'Completa' } else { 'Enlazada' })))
        [void]$NuevaResLineas.Children.Add((Fila-Resumen 'RAM' $(if ($mb -ge 512) { "$(Gb-Texto $mb) GB" } else { '—' })))
        [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Procesadores' $(if ($cpus -ge 1) { [string]$cpus } else { '—' })))
        [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Red' $red))
        if ($b.EsWindows) { [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Dominio' $dominioTxt)) }
        [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Extras' $txtExtras))
        if ($NuevaDesechable.IsChecked) { [void]$NuevaResLineas.Children.Add((Fila-Resumen 'Desechable' 'Sí')) }

        $est = $(if ($completa) { 'La copia completa tarda unos minutos, según el tamaño de la base.' } else { 'La copia enlazada se hace en segundos.' })
        if ($b.ConAgente) { $est += "`nLuego se configura sola dentro (unos minutos)." }
        if ($b.ConAgente -and $b.EsWindows -and $modoAd -eq 1) { $est += "`nCrear el dominio tarda unos 10-15 minutos más." }
        $pieExtras = Texto-ResumenExtras $catExtras $idsExtras
        if ($pieExtras) { $est += "`n$pieExtras." }
        $NuevaResEstimacion.Text = $est

        $falta = ''
        if ($motivo) { $falta = $motivo }
        elseif ($mb -lt 512 -or $mb -gt 131072) { $falta = 'La RAM tiene que estar entre 0,5 y 128 GB.' }
        elseif ($cpus -lt 1 -or $cpus -gt 64) { $falta = 'Los procesadores tienen que ser entre 1 y 64.' }
        elseif ($vram -lt 0 -or $vram -gt 8192) { $falta = 'La memoria 3D tiene que estar entre 0 y 8192 MB.' }
        $NuevaResAviso.Text = $falta
        $NuevaResAviso.Visibility = $(if ($falta) { 'Visible' } else { 'Collapsed' })

        if (([datetime]::Now - $script:cacheComprobNueva.Hora).TotalSeconds -gt 15) {
            $vm = $null; try { $vm = Buscar-Vmrun -Silencioso } catch {}
            $script:cacheComprobNueva.Vmware = [bool]$vm
            $script:cacheComprobNueva.Pass = (Test-Path (Join-Path $dirFc 'password.sec'))
            $script:cacheComprobNueva.Hora = [datetime]::Now
        }
        $NuevaResChecks.Children.Clear()
        [void]$NuevaResChecks.Children.Add((Fila-Comprobacion ([bool]$b.ConAgente) 'Base preparada para configurarse sola' 'Rehazla en «Crear base».'))
        [void]$NuevaResChecks.Children.Add((Fila-Comprobacion (-not $motivo) $(if ($nombre) { 'Nombre válido y libre' } else { 'Nombre elegido' }) $(if ($motivo) { $motivo } else { '' })))
        if ($b.ConAgente -and $NuevaIpFija.IsChecked) {
            $ipTxt = $NuevaIp.Text.Trim()
            $enUso = @($script:clones | Where-Object { $_.IP -and $_.IP -eq $ipTxt }).Count -gt 0
            $okIp = ((Es-IPv4 $ipTxt) -and -not $enUso)
            [void]$NuevaResChecks.Children.Add((Fila-Comprobacion $okIp 'IP válida y sin usar' $(if ($enUso) { 'Otra máquina ya usa esa IP.' } else { 'Escribe una IP correcta.' })))
        }
        [void]$NuevaResChecks.Children.Add((Fila-Comprobacion $script:cacheComprobNueva.Vmware 'VMware instalado' 'Instala VMware Workstation.'))
        $libre = -1.0
        try { $libre = ([IO.DriveInfo]([IO.Path]::GetPathRoot([string]$Config.CarpetaVMs))).AvailableFreeSpace / 1GB } catch {}
        if ($libre -ge 0) {
            $necesita = $(if ($completa) { [Math]::Ceiling(([double]$script:tamBasesNueva[[string]$b.Nombre] / 1GB) + 5) } else { 5 })
            [void]$NuevaResChecks.Children.Add((Fila-Comprobacion ($libre -ge $necesita) "Espacio libre: $([int]$libre) GB (hacen falta unos $necesita)" 'Libera espacio o cambia la carpeta de máquinas en Ajustes → Este PC.'))
        }
        [void]$NuevaResChecks.Children.Add((Fila-Comprobacion $script:cacheComprobNueva.Pass 'Contraseña de las máquinas guardada' 'Se te pedirá al empezar (se guarda cifrada).'))
    } catch { Escribir-Log ("Resumen de Nueva máquina: " + ($_ | Out-String)) }
}
$script:resNuevaClave = ''

function Colocar-ResumenNueva {
    try {
        $ancho = $PaginaNueva.ActualWidth
        if ($ancho -lt 50) { return }
        $abajo = ($ancho -lt 1000)
        if ($abajo -eq $script:nuevaResAbajo) { return }
        $script:nuevaResAbajo = $abajo
        $NuevaResHost.Content = $null
        [void]$NuevaPila.Children.Remove($NuevaResTarjeta)
        if ($abajo) {
            $NuevaResTarjeta.Margin = New-Object System.Windows.Thickness(0, 0, 0, 28)
            [void]$NuevaPila.Children.Add($NuevaResTarjeta)
            $NuevaResHost.Visibility = 'Collapsed'
            $NuevaColRes.Width = New-Object System.Windows.GridLength(0); $NuevaColGap.Width = New-Object System.Windows.GridLength(0)
        } else {
            $NuevaResTarjeta.Margin = New-Object System.Windows.Thickness(0, 2, 0, 28)
            $NuevaResHost.Content = $NuevaResTarjeta
            $NuevaResHost.Visibility = 'Visible'
            $NuevaColRes.Width = New-Object System.Windows.GridLength(300); $NuevaColGap.Width = New-Object System.Windows.GridLength(18)
        }
    } catch { Escribir-Log ("Colocar resumen de Nueva máquina: " + ($_ | Out-String)) }
}

function Cargar-BasesNueva {
    Iniciar-Espera
    try {
        $anterior = if (Base-Actual) { (Base-Actual).Nombre } else { Pref @('nueva', 'base') '' }
        $script:bases = @(Obtener-Bases)
        $script:clones = @(Leer-Clones)
        $script:red = Leer-RedNat
        if (-not $script:red) { $script:red = @{ Subred = '192.168.1.0'; Prefijo = 24; Puerta = '192.168.1.1' } }
        $script:tamBasesNueva = @{}
        foreach ($b in $script:bases) {
            $tam = 0.0
            try { $tam = Tamano-Carpeta (Split-Path $b.Vmx) } catch {}
            $script:tamBasesNueva[[string]$b.Nombre] = $tam
        }
        $NuevaBase.Items.Clear()
        foreach ($b in $script:bases) { [void]$NuevaBase.Items.Add($b.Nombre) }
        if ($script:bases.Count) {
            $NuevaVacio.Visibility = 'Collapsed'; $NuevaForm.Visibility = 'Visible'
            $i = [Array]::IndexOf([string[]]@($script:bases | ForEach-Object { $_.Nombre }), [string]$anterior)
            $NuevaBase.SelectedIndex = [Math]::Max(0, $i)
            Pintar-SelectorNueva
            $NuevaResumen.Text = "Una máquina de práctica a partir de una base  ·  $(Plural $script:bases.Count 'base disponible' 'bases disponibles')"
        } else {
            Poner-Vacio $NuevaVacio 'Ico_Base' 'Todavía no tienes ninguna base' 'Una base es el sistema ya instalado, de la que salen tus máquinas. Hazla una vez y la reutilizas.' 'Crear base' { $NavBase.IsChecked = $true } $true
            $NuevaVacio.Visibility = 'Visible'; $NuevaForm.Visibility = 'Collapsed'
            $NuevaBaseNota.Text = 'No hay bases: créalas en «Crear base».'
            $NuevaResumen.Text = 'Todavía no hay bases en este PC: crea una en «Crear base».'
            Cambio-BaseNueva
            $NuevaSelector.Children.Clear()
        }
    } finally { Terminar-Espera }
}

function Entrar-Nueva {
    # Al volver a la página no se pierde lo que estabas rellenando: solo se recarga todo si han
    # cambiado las bases; las máquinas se releen siempre (para proponer IPs libres)
    $nombres = (@(Obtener-Bases | ForEach-Object { $_.Nombre }) -join '|')
    if (-not $script:basesLeidas -or $nombres -ne (@($script:bases | ForEach-Object { $_.Nombre }) -join '|')) {
        Cargar-BasesNueva
        $script:basesLeidas = $true
    } else {
        $script:clones = @(Leer-Clones)
        Pintar-SelectorNueva
        Actualizar-RedNueva
        Actualizar-ResumenNueva
    }
    Pintar-ProgresoNueva
}

# ---------------------------------------------------------------- progreso de las máquinas nuevas
# Una fila por máquina que se está configurando o que terminó hace poco (2 horas): paso, barra y
# contador desde que se creó. Se repinta cada segundo mientras se ve la página.
$filaProgXaml = @'
<Border xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        CornerRadius="10" Background="{DynamicResource T_pie}" BorderBrush="{DynamicResource T_linea}" BorderThickness="1" Padding="14,11" Margin="0,0,0,8">
  <Grid>
    <Grid.ColumnDefinitions><ColumnDefinition Width="*"/><ColumnDefinition Width="Auto"/></Grid.ColumnDefinitions>
    <Grid.RowDefinitions><RowDefinition Height="Auto"/><RowDefinition Height="Auto"/></Grid.RowDefinitions>
    <StackPanel>
      <TextBlock x:Name="ProgNombre" FontWeight="SemiBold" Foreground="{DynamicResource T_texto}"/>
      <TextBlock x:Name="ProgPaso" FontSize="12.5" Margin="0,2,0,0" TextTrimming="CharacterEllipsis"/>
    </StackPanel>
    <StackPanel Grid.Column="1" Margin="14,0,0,0">
      <TextBlock x:Name="ProgReloj" FontSize="18" FontWeight="SemiBold" Foreground="{DynamicResource T_texto}" TextAlignment="Right"/>
      <TextBlock x:Name="ProgRelojNota" FontSize="11.5" Foreground="{DynamicResource T_textoSuave}" TextAlignment="Right"/>
    </StackPanel>
    <ProgressBar x:Name="ProgBarra" Grid.Row="1" Grid.ColumnSpan="2" Style="{StaticResource Progreso}" Height="6" Maximum="100" Margin="0,9,0,0"/>
    <Border x:Name="ProgRayos" Grid.Row="1" Grid.ColumnSpan="2" Margin="-30,-16,-30,-26" IsHitTestVisible="False"/>
  </Grid>
</Border>
'@
$script:filasProgNueva = @{}

function Pintar-ProgresoNueva {
    $ahoraEp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $entradas = @((Leer-ProgresoVm).GetEnumerator() | Where-Object {
        $e = $_.Value
        # (las de un laboratorio salen en la página «Laboratorio»)
        $e.enCurso -and -not $e.lab -and (($finalesProg -notcontains [string]$e.estado) -or ($ahoraEp - [int64]$e.inicio) -lt 7200) })
    # Primero las que siguen configurándose; luego las terminadas, de la más reciente a la más antigua
    $entradas = @($entradas | Sort-Object @{ Expression = { $finalesProg -contains [string]$_.Value.estado } }, @{ Expression = { [int64]$_.Value.creada }; Descending = $true })
    $NuevaProgCaja.Visibility = $(if ($entradas.Count) { 'Visible' } else { 'Collapsed' })
    $vistas = @{}
    $orden = 0
    foreach ($par in $entradas) {
        $clave = [string]$par.Key; $e = $par.Value; $vistas[$clave] = $true
        $fp = $script:filasProgNueva[$clave]
        if (-not $fp) {
            $raizFila = [Windows.Markup.XamlReader]::Parse($filaProgXaml)
            $fp = Elementos $raizFila $filaProgXaml
            $fp.Raiz = $raizFila
            $script:filasProgNueva[$clave] = $fp
            # Entra con un fundido
            $raizFila.Opacity = 0
            Animar $raizFila $propOpacidad 1 300 0
        }
        if ($NuevaProgLista.Children.IndexOf($fp.Raiz) -ne $orden) {
            if ($NuevaProgLista.Children.Contains($fp.Raiz)) { $NuevaProgLista.Children.Remove($fp.Raiz) }
            $NuevaProgLista.Children.Insert($orden, $fp.Raiz)
        }
        $orden++
        $i = Info-Paso $e
        $final = $finalesProg -contains [string]$e.estado
        $total = Tiempo-Total $e
        $fp.ProgNombre.Text = [string]$e.nombre + $(if ($e.lab) { "  ·  laboratorio $($e.lab)" } else { '' })
        if ($final -and [string]$e.estado -eq 'ok') { $fp.ProgPaso.Text = 'Lista para usar' }
        elseif ($i.SinDatos) { $fp.ProgPaso.Text = 'Sin datos: ¿la base no tiene VMware Tools?' }
        else { $fp.ProgPaso.Text = $i.Largo + $(if ($i.Tiempo -and -not $final) { "  ·  este paso: $($i.Tiempo)" } else { '' }) }
        $fp.ProgPaso.Foreground = Pincel $(if ($final -or $i.SinDatos) { $i.Color } else { $Colores.Suave })
        $fp.ProgReloj.Text = $(if ($total -ge 0) { Formato-Tiempo $total } else { '' })
        $fp.ProgReloj.Foreground = Pincel $(if ($final) { $i.Color } else { '#12261A' })
        $fp.ProgRelojNota.Text = $(if ($total -lt 0) { '' } elseif ($final) { 'tardó en total' } else { 'desde que se creó' })
        $fp.ProgBarra.Foreground = Pincel $i.Color
        if ([Math]::Abs($fp.ProgBarra.Value - $i.Pct) -gt 0.5) {
            $an = New-Object System.Windows.Media.Animation.DoubleAnimation
            $an.To = [double]$i.Pct
            $an.Duration = New-Object System.Windows.Duration([TimeSpan]::FromMilliseconds(200))
            $fp.ProgBarra.BeginAnimation([System.Windows.Controls.Primitives.RangeBase]::ValueProperty, $an)
        }
        Brillo-Barra $fp.ProgBarra ([double]$i.Pct) ([string]$i.Color)
        # «Lista para usar»: la barra rebosa energía (rayitos alrededor, sin parar mientras se vea). Si se vio configurándose,
        # al acabar sale además una ráfaga
        if (-not $final) { $fp.VistaEnCurso = $true; Parar-RayosBarra $fp.ProgRayos }
        elseif ([string]$e.estado -eq 'ok') {
            $rafagaN = ($fp.VistaEnCurso -and -not $fp.Celebrada)
            if ((Rayos-Barra $fp.ProgRayos $fp.ProgBarra $rafagaN) -and $rafagaN) { $fp.Celebrada = $true }
        } else { Parar-RayosBarra $fp.ProgRayos }
    }
    foreach ($k in @($script:filasProgNueva.Keys)) {
        if (-not $vistas.ContainsKey($k)) { Olvidar-RayosBarra $script:filasProgNueva[$k].ProgRayos; $NuevaProgLista.Children.Remove($script:filasProgNueva[$k].Raiz); $script:filasProgNueva.Remove($k) }
    }
}

# Valores de siempre (los últimos que elegiste)
$NuevaRam.Text = Gb-Texto ([double](Pref @('nueva', 'ram') $Config.RAM_MB))
$NuevaCpu.Text = [string](Pref @('nueva', 'cpus') $Config.CPUs)
$NuevaVram.Text = [string](Pref @('nueva', 'vram') $(if ($null -ne $Config.VRAM_MB) { [int]$Config.VRAM_MB } else { 1024 }))
if ((Pref @('nueva', 'tipo') 'linked') -eq 'full') { $NuevaCompleta.IsChecked = $true }
$NuevaArrancar.IsChecked = [bool](Pref @('nueva', 'arrancar') $true)

# ---------------------------------------------------------------- eventos
# Etiquetas opcionales de la máquina nueva (ficha 18). Las copias no heredan las de la base
$script:editorEtqNueva = Nuevo-EditorEtiquetas
$script:editorEtqNueva.Sugerir = { Etiquetas-Usadas }
$NuevaHuecoEtq.Content = $script:editorEtqNueva.Raiz

$NuevaBase.Add_SelectionChanged({ Cambio-BaseNueva })
$BtnNuevaRecargar.Add_Click({ Cargar-BasesNueva; Mostrar-Toast 'Bases y máquinas leídas de nuevo.' 'info' })
$NuevaNombre.Add_TextChanged({
    $nom = $NuevaNombre.Text.Trim()
    if (-not $script:hostEditado) {
        $script:rellenandoHost = $true
        $NuevaHost.Text = $(if ($nom) { Nombre-Equipo $nom } else { '' })
        $script:rellenandoHost = $false
    }
    $motivo = if ($nom) { Validar-NombreMaquina $nom } else { $null }
    $NuevaNombreNota.Text = $(if ($motivo) { $motivo } else { 'También será el nombre de su carpeta.' })
    $NuevaNombreNota.Foreground = Pincel $(if ($motivo) { $Colores.Error } else { $Colores.Suave })
})
$NuevaHost.Add_TextChanged({ if (-not $script:rellenandoHost) { $script:hostEditado = [bool]$NuevaHost.Text } })
$NuevaIpFija.Add_Checked({ if (-not $NuevaIp.Text) { Proponer-RedNueva }; Actualizar-RedNueva })
$NuevaIpFija.Add_Unchecked({ Actualizar-RedNueva })
$NuevaAd.Add_SelectionChanged({
    $b = Base-Actual
    if ($NuevaAd.SelectedIndex -eq 1 -and $b -and -not $b.EsServidor) { $NuevaAd.SelectedIndex = 0; return }
    if ($NuevaAd.SelectedIndex -eq 1) { $NuevaIp.Text = '' }
    if ($NuevaAd.SelectedIndex -ge 0) { Actualizar-AdNueva }
})
$NuevaDominio.Add_TextChanged({
    $d = $NuevaDominio.Text.Trim().ToLower()
    $nb = ($d.Split('.')[0] -replace '[^a-zA-Z0-9-]', '').ToUpper()
    if ($nb.Length -gt 15) { $nb = $nb.Substring(0, 15) }
    $conocido = @(Dominios-Conocidos) | Where-Object { $_.Dominio -eq $d } | Select-Object -First 1
    if ($conocido) {
        $NuevaDcIp.Text = $conocido.IP
        $NuevaNetbios.Text = $(if ($conocido.Netbios) { $conocido.Netbios } else { $nb })
        if ($NuevaIpFija.IsChecked) { $NuevaDns.Text = $conocido.IP }
    } else { $NuevaNetbios.Text = $nb }
})
$NuevaDcIp.Add_TextChanged({
    if ($NuevaAd.SelectedIndex -eq 2 -and $NuevaIpFija.IsChecked -and (Es-IPv4 $NuevaDcIp.Text.Trim())) { $NuevaDns.Text = $NuevaDcIp.Text.Trim() }
})
# Las desechables siempre son enlazadas (se crean en segundos)
$NuevaDesechable.Add_Checked({ $NuevaEnlazada.IsChecked = $true; $NuevaCompleta.IsEnabled = $false })
$NuevaDesechable.Add_Unchecked({ $NuevaCompleta.IsEnabled = $true })


# El resumen de la derecha se repone con cada cambio
$NuevaNombre.Add_TextChanged({ Actualizar-ResumenNueva })
$NuevaHost.Add_TextChanged({ Actualizar-ResumenNueva })
foreach ($cajaN in $NuevaRam, $NuevaCpu, $NuevaVram, $NuevaIp, $NuevaDominio) { $cajaN.Add_TextChanged({ Actualizar-ResumenNueva }) }
$NuevaEnlazada.Add_Checked({ Actualizar-ResumenNueva })
$NuevaCompleta.Add_Checked({ Actualizar-ResumenNueva })
$NuevaIpFija.Add_Checked({ Actualizar-ResumenNueva })
$NuevaIpFija.Add_Unchecked({ Actualizar-ResumenNueva })
$NuevaDesechable.Add_Checked({ Actualizar-ResumenNueva })
$NuevaDesechable.Add_Unchecked({ Actualizar-ResumenNueva })
$NuevaAd.Add_SelectionChanged({ Actualizar-ResumenNueva })
$BtnNuevaRamMenos.Add_Click({ Paso-Cifra $NuevaRam -0.5 0.5 128 })
$BtnNuevaRamMas.Add_Click({ Paso-Cifra $NuevaRam 0.5 0.5 128 })
$BtnNuevaCpuMenos.Add_Click({ Paso-Cifra $NuevaCpu -1 1 64 })
$BtnNuevaCpuMas.Add_Click({ Paso-Cifra $NuevaCpu 1 1 64 })
$BtnNuevaVramMenos.Add_Click({ Paso-Cifra $NuevaVram -128 0 8192 })
$BtnNuevaVramMas.Add_Click({ Paso-Cifra $NuevaVram 128 0 8192 })
$BtnNuevaIrBase.Add_Click({ $NavBase.IsChecked = $true })
$PaginaNueva.Add_SizeChanged({ Colocar-ResumenNueva })
$BtnCrearMaquina2.Add_Click({ Crear-MaquinaNueva })

# ---------------------------------------------------------------- crear
function Crear-MaquinaNueva {
    $b = Base-Actual
    if (-not $b) { Aviso 'No hay ninguna base. Crea una en «Crear base».'; return }
    $nombre = $NuevaNombre.Text.Trim()
    $motivo = Validar-NombreMaquina $nombre
    if ($motivo) { Aviso $motivo; [void]$NuevaNombre.Focus(); return }
    # Lo que haya escrito en «Etiquetas» sin pulsar Enter cuenta; si no vale, el propio campo lo avisa
    if (-not (Etq-Pendiente $script:editorEtqNueva)) { return }
    $hostname = Nombre-Equipo $(if ($NuevaHost.Text.Trim()) { $NuevaHost.Text.Trim() } else { $nombre })
    $ram = Texto-AMb $NuevaRam.Text; $cpus = Numero $NuevaCpu.Text; $vram = Numero $NuevaVram.Text
    if ($ram -lt 512 -or $ram -gt 131072) { Aviso 'La RAM tiene que ser un número de GB entre 0,5 y 128 (por ejemplo 4).'; return }
    if ($cpus -lt 1 -or $cpus -gt 64) { Aviso 'Los procesadores tienen que ser un número entre 1 y 64.'; return }
    if ($vram -lt 0 -or $vram -gt 8192) { Aviso 'La memoria 3D tiene que ser un número de MB entre 0 y 8192 (0 = sin aceleración 3D).'; return }

    $ip = $null; $ad = $null; $extras = @(); $actualizar = $false; $paquetes = @()
    if ($b.ConAgente) {
        if ($NuevaIpFija.IsChecked) {
            $dns = @($NuevaDns.Text -split '\s*,\s*' | Where-Object { $_ })
            $pre = Numero $NuevaPrefijo.Text
            if (-not (Es-IPv4 $NuevaIp.Text.Trim())) { Aviso 'La IP no es válida.'; return }
            if ($pre -lt 1 -or $pre -gt 32) { Aviso 'El prefijo tiene que ser un número del 1 al 32 (por ejemplo 24).'; return }
            if (-not (Es-IPv4 $NuevaGw.Text.Trim())) { Aviso 'La puerta de enlace no es válida.'; return }
            if (-not $dns.Count -or ($dns | Where-Object { -not (Es-IPv4 $_) })) { Aviso 'Algún DNS no es válido (sepáralos por comas).'; return }
            $ip = @{ addr = $NuevaIp.Text.Trim(); prefix = $pre; gw = $NuevaGw.Text.Trim(); dns = $dns }
        }
        $marcadas = @(Marcados-SelectorExtras $script:selExtrasNueva)
        if ($b.EsWindows) {
            if ($NuevaAd.SelectedIndex -gt 0) {
                $dom = $NuevaDominio.Text.Trim().ToLower()
                if (-not (Es-Dominio $dom)) { Aviso 'El nombre de dominio no es válido (ejemplo: empresa.local).'; return }
                $nb = $NuevaNetbios.Text.Trim().ToUpper()
                if ($nb -notmatch '^[A-Z0-9-]{1,15}$') { Aviso 'El nombre NetBIOS no es válido (letras, números y guiones, máximo 15).'; return }
                if ($NuevaAd.SelectedIndex -eq 1) {
                    $ad = @{ modo = 'dc'; dominio = $dom; netbios = $nb; dcip = $ip.addr }
                } else {
                    if (-not (Es-IPv4 $NuevaDcIp.Text.Trim())) { Aviso 'La IP del controlador de dominio no es válida.'; return }
                    $ad = @{ modo = 'unir'; dominio = $dom; netbios = $nb; dcip = $NuevaDcIp.Text.Trim() }
                }
            }
            $extras = $marcadas
            if (@($extras | Where-Object { $ExtrasAnidados -contains $_ }).Count -and $ram -lt 8192) {
                if (-not (Pregunta "Hyper-V, Sandbox y WSL van justos con menos de 8 GB de RAM.`n¿Crear la máquina igualmente con $(Gb-Texto $ram) GB?" 'Poca RAM' 'Crear igualmente')) { return }
            }
        } else {
            $actualizar = [bool]$NuevaActualizar.IsChecked
            $paquetes = @($marcadas)
            if (($paquetes -contains 'apache') -and ($paquetes -contains 'nginx')) {
                if (-not (Pregunta "Apache y Nginx usan el puerto 80: uno de los dos no arrancará.`n¿Seguir igualmente?" 'Puerto 80' 'Seguir')) { return }
            }
            if (($paquetes -contains 'proftpd') -and ($paquetes -contains 'vsftpd')) {
                if (-not (Pregunta "ProFTPD y vsftpd usan el puerto 21: uno de los dos no arrancará.`n¿Seguir igualmente?" 'Puerto 21' 'Seguir')) { return }
            }
        }
    }

    $pedido = [ordered]@{
        base = $b.Nombre; nombre = $nombre; hostname = $hostname
        tipo = $(if ($NuevaCompleta.IsChecked) { 'full' } else { 'linked' })
        ram = $ram; cpus = $cpus; vram = $vram
        zona = (Clave-Combo $NuevaZona)
        ip = $ip; ad = $ad; extras = @($extras); actualizar = $actualizar; paquetes = @($paquetes)
        arrancar = [bool]$NuevaArrancar.IsChecked
        desechable = [bool]$NuevaDesechable.IsChecked
        etiquetas = @(Etq-Obtener $script:editorEtqNueva)
    }
    if (-not (Asegurar-PasswordVms)) { return }   # la contraseña se pide en una ventana, nunca en la consola
    Lanzar 'nueva-maquina.ps1' $pedido

    # Recordar lo elegido (mismo archivo que la ventana de siempre)
    $sw = @(); if ($actualizar) { $sw += 'actualizar' }; $sw += $paquetes
    Guardar-Prefs ([ordered]@{
        pestana   = 0
        nueva     = [ordered]@{
            base = $b.Nombre; tipo = $pedido.tipo; ram = $ram; cpus = $cpus; vram = $vram
            arrancar = [bool]$NuevaArrancar.IsChecked
            win = [ordered]@{ extras = $(if ($b.EsWindows) { @($extras) } else { @(Pref @('nueva', 'win', 'extras') @()) }) }
            ubu = [ordered]@{ software = $(if (-not $b.EsWindows) { @($sw) } else { @(Pref @('nueva', 'ubu', 'software') @()) }) }
        }
        crearBase = Pref @('crearBase') $null
    })

    # Para la siguiente: esta IP cuenta como usada
    if ($ip) { $script:clones += [pscustomobject]@{ Nombre = $nombre; IP = $ip.addr; Dominio = $(if ($ad -and $ad.modo -eq 'dc') { $ad.dominio }); Netbios = $(if ($ad) { $ad.netbios }) } }
    Mostrar-Toast "Creando «$nombre»: el progreso sale en la consola que se ha abierto. Luego aparecerá en Mis máquinas."
    $script:hostEditado = $false
    $NuevaNombre.Text = ''; $NuevaIp.Text = ''
    Etq-Poner $script:editorEtqNueva @()
    Actualizar-AdNueva
}
$BtnCrearMaquina.Add_Click({ Crear-MaquinaNueva })
