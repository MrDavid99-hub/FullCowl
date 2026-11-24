# =====================================================================
#  Interfaz nueva: temas (Claro / Oscuro / Automático)
#  Los colores tienen nombre (T_<nombre>) y viven en los recursos de la aplicación; las pantallas
#  los piden con DynamicResource, así que al cambiar de tema se actualizan solas, sin reiniciar.
#  Aquí está la paleta. Los colores que se ponen desde el código (Pincel '#xxxxxx') se traducen al tema
#  actual con Hex-Tema (la tabla $script:HexANombre dice a qué nombre corresponde cada color claro).
# =====================================================================
$script:Paleta = [ordered]@{
    fondo = @('#F2F6F3', '#0B1310')
    bienvenida = @('#12261A', '#121C19')
    texto = @('#14231A', '#E6F5F1')
    textoSuave = @('#5F6F65', '#9DB5AE')
    superficie = @('#FFFFFF', '#151A19')
    borde = @('#DCE6DF', '#2E3C39')
    linea = @('#E6EDE8', '#232F2B')
    pista = @('#E3F1E7', '#232F2B')
    neutro = @('#EEF2EF', '#1C2623')
    infoFondo = @('#EEF5F0', '#14251F')
    pie = @('#F7FAF8', '#101614')
    acento = @('#39824D', '#52BEA2')
    acentoClaro = @('#2D6A3E', '#74D2BA')
    bordeHover = @('#A9D3B6', '#3D7266')
    bordeFuerte = @('#B9C9BE', '#5F6F6A')
    destacado = @('#78EBDD', '#52BEA2')
    sobreDestacado = @('#12261A', '#040505')
    sobreAcento = @('#FFFFFF', '#040505')
    menuSel = @('#1F3D2B', '#2E3C39')
    menuHover = @('#1B3825', '#161819')
    mosaico = @('#1F3D2B', '#1F2E2A')
    peligro = @('#C62828', '#E5534B')
    peligroBoton = @('#C62828', '#BF3A31')
    peligroHover = @('#A31F1F', '#A92F28')
    peligroFondo = @('#FDEEEE', '#2E1A1A')
    peligroBorde = @('#F0D5D5', '#4D2A28')
    peligroBordeHover = @('#E8AFAF', '#7A3A36')
    avisoFondo = @('#FFF7E0', '#2B2512')
    avisoBorde = @('#EBD9A6', '#4A3F1E')
    avisoTexto = @('#6B5414', '#E6C65C')
    aviso = @('#8A6D1F', '#D9B94F')
    encendida = @('#2A9D8F', '#52BEA2')
    encendidaFondo = @('#DDF5F1', '#173028')
    oliva = @('#7A7A3C', '#B5B56A')
    olivaFondo = @('#EFEFDF', '#2A2A1A')
    placeholder = @('#8A9A90', '#75897F')
    esqueleto1 = @('#C9D6CD', '#2A3532')
    esqueleto2 = @('#9FB3A6', '#3A4743')
    ventanaHover = @('#E3EAE5', '#1F2724')
    ok = @('#2F7A45', '#52BEA2')
    brillo = @('#78EBDD', '#D0FFF5')
    campo = @('#EEF4F0', '#1F2E2A')
    textoMenu = @('#BFD3C6', '#9DB5AE')
    menuAcento = @('#78EBDD', '#78EBDD')
}

# Color de acento (ficha 8 y 23): por cada uno y tema, @(acento, enlace, texto sobre acento). Esmeralda se quitó (ficha 23): quien
# la tuviera guardada pasa a Full Cowl (Migrar-Acento).
$script:Acentos = [ordered]@{
    FullCowl  = @(@('#39824D', '#2D6A3E', '#FFFFFF'), @('#52BEA2', '#74D2BA', '#040505'))
    Dorado    = @(@('#D9A416', '#8A6508', '#12261A'), @('#F5C52E', '#F8D769', '#1A1403'))
    Azul      = @(@('#2F6FDE', '#2456B5', '#FFFFFF'), @('#6EA8FE', '#9CC3FF', '#04101F'))
    Violeta   = @(@('#7B4FD8', '#6338B8', '#FFFFFF'), @('#C792EA', '#DDB6F4', '#1A0B24'))
    Rojo      = @(@('#C73A33', '#B1342D', '#FFFFFF'), @('#F07169', '#F79A94', '#240806'))
    Grafito   = @(@('#5B6770', '#434E56', '#FFFFFF'), @('#A9B6BD', '#C4CED3', '#0B0D0E'))
}
$script:NombresAcento = @{ FullCowl = 'Full Cowl'; Dorado = 'Dorado'; Azul = 'Azul'; Violeta = 'Violeta'; Rojo = 'Rojo'; Grafito = 'Grafito' }

# Modo sobrio (para clase): paleta apagada y gris; el acento pasa a ser un gris fijo. Lo que no sale en la tabla de la ficha
# se ha deducido en gris para que no quede nada verde.
$script:PaletaSobria = @{
    fondo = @('#F3F4F5', '#111314'); bienvenida = @('#26292C', '#070808'); texto = @('#1D2023', '#E8EAEB')
    textoSuave = @('#60676D', '#9AA2A8'); superficie = @('#FFFFFF', '#1A1D1F'); borde = @('#DADDE0', '#2F3437')
    linea = @('#E4E6E8', '#26292C'); pista = @('#D5D9DC', '#33383B'); neutro = @('#ECEEF0', '#24282B')
    campo = @('#ECEEF0', '#24282B'); infoFondo = @('#F0F2F3', '#1D2022'); pie = @('#F7F8F9', '#151718')
    acento = @('#4A5560', '#9AA9B0'); acentoClaro = @('#394149', '#B8C3C8'); sobreAcento = @('#FFFFFF', '#0B0D0E')
    destacado = @('#4A5560', '#9AA9B0'); sobreDestacado = @('#FFFFFF', '#0B0D0E'); menuAcento = @('#9AA9B0', '#9AA9B0')
    bordeHover = @('#B4BABF', '#4A5560'); bordeFuerte = @('#B4BABF', '#5A6166')
    menuSel = @('#3A3F43', '#2A2E31'); menuHover = @('#303538', '#1A1D1F'); textoMenu = @('#C3C8CC', '#9AA2A8')
    mosaico = @('#3A3F43', '#2A2E31'); encendida = @('#4A5560', '#9AA9B0'); encendidaFondo = @('#E3E6E8', '#24282B')
    oliva = @('#6A7075', '#9AA2A8'); olivaFondo = @('#ECEEF0', '#24282B'); placeholder = @('#8A9096', '#6F767B')
    esqueleto1 = @('#D5D9DC', '#33383B'); esqueleto2 = @('#B4BABF', '#454B4F'); ventanaHover = @('#E4E6E8', '#26292C')
    ok = @('#4A5560', '#9AA9B0'); brillo = @('#B4BABF', '#B8C3C8')
}
$script:sobrioActual = $false
$script:acentoActual = 'FullCowl'

# Color de toda la interfaz (ficha 23): fondo, menú, tarjetas, campos y bordes tomados del color elegido. Full Cowl usa la
# paleta de siempre ($script:Paleta). Claro: fondo, menú, menú elegido, menú hover, texto del menú, campo, borde, texto, texto suave
# (la tarjeta es blanca). Oscuro: fondo, menú, menú elegido, tarjeta, campo, borde, texto, texto suave (hover del menú = tarjeta,
# texto del menú = texto suave). En los dos, la «pista» de barras e interruptores es el borde.
$script:ColoresTotal = @{
    Dorado  = @{ Claro = @('#F8F5EC', '#2E2308', '#5A430E', '#43330B', '#E6D6A8', '#F3EEDD', '#E6DDC0', '#2A2208', '#7A6D4A')
                 Oscuro = @('#15110A', '#0A0803', '#43361F', '#1F190E', '#302717', '#43361F', '#F6EEDC', '#BDAE8C') }
    Azul    = @{ Claro = @('#EFF4FC', '#0F2247', '#1C3E80', '#162F61', '#BCCDEE', '#E6EEFA', '#D2DEF2', '#0E1D3B', '#55658A')
                 Oscuro = @('#0A1220', '#040810', '#26395B', '#111B2E', '#1A2A45', '#26395B', '#E6EEFC', '#9FB2D4') }
    Violeta = @{ Claro = @('#F5F0FB', '#261343', '#47257C', '#341B5C', '#D3C2EE', '#EEE6F8', '#DDD0EE', '#231238', '#6C5A8A')
                 Oscuro = @('#120C1B', '#07040C', '#3B2B55', '#1B1328', '#2A1E3E', '#3B2B55', '#F1E8FA', '#B8A5D0') }
    Rojo    = @{ Claro = @('#FBF0F0', '#3A0F14', '#6C1B24', '#4F141B', '#F0C4C8', '#F6E6E7', '#EBD1D3', '#3A1014', '#8A5A60')
                 Oscuro = @('#17090C', '#0B0305', '#4A2630', '#220F13', '#341A20', '#4A2630', '#F8E8EA', '#C9A3AA') }
    Grafito = @{ Claro = @('#F3F4F5', '#26292C', '#3A3F43', '#303538', '#C3C8CC', '#ECEEF0', '#DADDE0', '#1D2023', '#60676D')
                 Oscuro = @('#111314', '#070808', '#2A2E31', '#1A1D1F', '#24282B', '#2F3437', '#E8EAEB', '#9AA2A8') }
}
$script:colorTotalActual = $true
$script:paletaTotal = $null   # @(claro, oscuro): nombre -> color; $null si no toca (Full Cowl, solo acento o modo sobrio)

function Mezcla-Hex([string]$hexIni, [string]$hexFin, [double]$parte) {
    # Mezcla dos colores #RRGGBB: 0 = el primero, 1 = el segundo
    $c1 = $hexIni.TrimStart('#'); $c2 = $hexFin.TrimStart('#'); $res = '#'
    for ($k = 0; $k -lt 6; $k += 2) {
        $x1 = [Convert]::ToInt32($c1.Substring($k, 2), 16); $x2 = [Convert]::ToInt32($c2.Substring($k, 2), 16)
        $res += ([int][Math]::Round($x1 + ($x2 - $x1) * $parte)).ToString('X2')
    }
    return $res
}

function Escalar-Hex([string]$hexOrig, [double]$factor) {
    $c1 = $hexOrig.TrimStart('#'); $res = '#'
    for ($k = 0; $k -lt 6; $k += 2) {
        $x1 = [Convert]::ToInt32($c1.Substring($k, 2), 16)
        $res += ([int][Math]::Min(255, [Math]::Max(0, [Math]::Round($x1 * $factor)))).ToString('X2')
    }
    return $res
}

function Construir-PaletaColor([string]$color, [int]$i) {
    # Todos los nombres de la paleta para ese color y tema (0 claro, 1 oscuro), a partir de la tabla de la ficha 23. Lo que la
    # ficha no da (línea, pie, estados de ratón...) se deduce mezclando. Colores de estado (peligro, aviso, encendida) no se tocan.
    $d = $script:ColoresTotal[$color]
    if (-not $d) { return $null }
    $q = @{}
    if ($i -eq 0) {
        $v = $d.Claro
        $q.fondo = $v[0]; $q.bienvenida = $v[1]; $q.menuSel = $v[2]; $q.menuHover = $v[3]; $q.textoMenu = $v[4]
        $q.campo = $v[5]; $q.borde = $v[6]; $q.texto = $v[7]; $q.textoSuave = $v[8]; $q.superficie = '#FFFFFF'
        $q.menuA = Escalar-Hex $v[1] 1.2; $q.menuB = Escalar-Hex $v[1] 0.82
        $q.neutro = $q.campo; $q.pie = Mezcla-Hex $q.fondo '#FFFFFF' 0.5
        $q.mosaico = $q.menuSel; $q.ventanaHover = Mezcla-Hex $q.borde $q.fondo 0.5
        $factorE1 = 0.2; $factorE2 = 0.45
    } else {
        $v = $d.Oscuro
        $q.fondo = $v[0]; $menuO = $v[1]; $q.menuSel = $v[2]; $q.superficie = $v[3]; $q.campo = $v[4]; $q.borde = $v[5]
        $q.texto = $v[6]; $q.textoSuave = $v[7]
        $q.menuHover = $q.superficie; $q.textoMenu = $q.textoSuave
        $q.menuA = Mezcla-Hex $menuO '#FFFFFF' 0.015; $q.menuB = $menuO
        $q.bienvenida = Mezcla-Hex $q.fondo $q.campo 0.45
        $q.neutro = Mezcla-Hex $q.superficie $q.campo 0.5; $q.pie = Mezcla-Hex $q.fondo $q.superficie 0.5
        $q.mosaico = $q.campo; $q.ventanaHover = Mezcla-Hex $q.superficie $q.campo 0.5
        $factorE1 = 0.1; $factorE2 = 0.25
    }
    $q.pista = $q.borde
    $q.linea = Mezcla-Hex $q.borde $q.fondo 0.4
    $q.infoFondo = $q.neutro
    $q.bordeHover = Mezcla-Hex $q.borde $script:Acentos[$color][$i][0] 0.4
    $q.bordeFuerte = Mezcla-Hex $q.borde $q.textoSuave 0.35
    $q.placeholder = Mezcla-Hex $q.textoSuave $q.fondo 0.3
    $q.esqueleto1 = Mezcla-Hex $q.borde $q.textoSuave $factorE1
    $q.esqueleto2 = Mezcla-Hex $q.borde $q.textoSuave $factorE2
    return $q
}

function Migrar-Acento {
    # Esmeralda ya no existe (ficha 23): pasa a Full Cowl
    if ([string]$Config.Acento -eq 'Esmeralda') {
        try { Guardar-ConfigLocal @{ Acento = 'FullCowl' } } catch { $Config.Acento = 'FullCowl' }
    }
}
$script:HexANombre = @{
    '39824D' = 'acento'
    '2D6A3E' = 'acentoClaro'
    '5F6F65' = 'textoSuave'
    'DCE6DF' = 'borde'
    '78EBDD' = 'menuAcento'
    '14231A' = 'texto'
    '12261A' = 'texto'
    'E6EDE8' = 'linea'
    'E6EEE8' = 'linea'
    'EEF5F0' = 'infoFondo'
    'EEF2EF' = 'neutro'
    'F2F6F3' = 'fondo'
    'F7FAF8' = 'pie'
    'C62828' = 'peligro'
    '8A6D1F' = 'aviso'
    '2F7A45' = 'ok'
    'E3F1E7' = 'pista'
    'E3F3E8' = 'pista'
    'FBF3DD' = 'avisoFondo'
    'FDECEC' = 'peligroFondo'
    '2A9D8F' = 'encendida'
    'B9C9BE' = 'bordeFuerte'
    'A9D3B6' = 'bordeHover'
    '6B5414' = 'avisoTexto'
    'EBD9A6' = 'avisoBorde'
}
$script:temaActual = 'claro'

function Windows-EsOscuro {
    # El tema de aplicaciones de Windows (Configuración > Personalización > Colores)
    try { return ((Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop) -eq 0) } catch { return $false }
}

function Tema-DeModo([string]$modo) {
    # 'Claro', 'Oscuro' o 'Automatico' (el de Windows) -> 'claro' u 'oscuro'
    if ($modo -eq 'Oscuro') { return 'oscuro' }
    if ($modo -eq 'Automatico') { return $(if (Windows-EsOscuro) { 'oscuro' } else { 'claro' }) }
    return 'claro'
}

function Tema-Efectivo {
    # El tema que toca según Ajustes (por defecto, Claro)
    return (Tema-DeModo ([string]$Config.Tema))
}

function Valor-Paleta([string]$n, [int]$i) {
    # El color de ese nombre en ese tema (0 claro, 1 oscuro), con el modo sobrio y el acento elegido
    if ($script:sobrioActual -and $script:PaletaSobria.ContainsKey($n)) { return $script:PaletaSobria[$n][$i] }
    $ac = $script:Acentos[$script:acentoActual]
    if ($ac -and $script:acentoActual -ne 'FullCowl') {
        switch ($n) {
            'acento' { return $ac[$i][0] }
            'acentoClaro' { return $ac[$i][1] }
            'sobreAcento' { return $ac[$i][2] }
            'destacado' { return $ac[$i][0] }
            'sobreDestacado' { return $ac[$i][2] }
            'menuAcento' { return $ac[1][0] }
        }
    }
    if ($script:paletaTotal -and $script:paletaTotal[$i].ContainsKey($n)) { return $script:paletaTotal[$i][$n] }
    return $script:Paleta[$n][$i]
}

function Aplicar-Tema([string]$tema, $sobrio = $null, $acento = $null, $colorTotal = $null) {
    # $sobrio, $acento y $colorTotal solo se pasan para ver un cambio de Ajustes antes de guardarlo; si no, los de Ajustes
    Migrar-Acento
    $script:sobrioActual = $(if ($null -ne $sobrio) { [bool]$sobrio } else { [bool]$Config.Sobrio })
    $nomAc = $(if ($null -ne $acento) { [string]$acento } else { [string]$Config.Acento })
    $script:acentoActual = $(if ($script:Acentos.Contains($nomAc)) { $nomAc } else { 'FullCowl' })
    # Color en toda la interfaz (por defecto sí); el modo sobrio y Full Cowl no cambian la paleta de fondos
    $script:colorTotalActual = $(if ($null -ne $colorTotal) { [bool]$colorTotal } else { $Config.ColorTotal -ne $false })
    $script:paletaTotal = $null
    if ($script:colorTotalActual -and -not $script:sobrioActual -and $script:ColoresTotal.ContainsKey($script:acentoActual)) {
        $script:paletaTotal = @((Construir-PaletaColor $script:acentoActual 0), (Construir-PaletaColor $script:acentoActual 1))
    }
    # Sustituye los pinceles con nombre: todo lo que los usa con DynamicResource cambia al instante
    $i = $(if ($tema -eq 'oscuro') { 1 } else { 0 })
    $app = [System.Windows.Application]::Current
    foreach ($n in $script:Paleta.Keys) {
        # Color y pincel creados sin envoltorio de PowerShell (si no, WPF no los reconoce al leer los XAML)
        $col = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString((Valor-Paleta $n $i)))
        $b = [System.Windows.Media.SolidColorBrush]::new($col)
        $b.Freeze()
        $app.Resources["T_$n"] = $b.psobject.BaseObject
    }
    # Degradado del menú (necesita colores, no pinceles)
    $hA = $(if ($script:paletaTotal) { $script:paletaTotal[$i].menuA } elseif ($script:sobrioActual) { $(if ($i) { '#0B0C0C' } else { '#2E3235' }) } else { $(if ($i) { '#070909' } else { '#173322' }) })
    $hB = $(if ($script:paletaTotal) { $script:paletaTotal[$i].menuB } elseif ($script:sobrioActual) { $(if ($i) { '#070808' } else { '#26292C' }) } else { $(if ($i) { '#040505' } else { '#0E1F15' }) })
    $cA = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($hA))
    $cB = [System.Windows.Media.Color]([System.Windows.Media.ColorConverter]::ConvertFromString($hB))
    $app.Resources['K_menuA'] = $cA
    $app.Resources['K_menuB'] = $cB
    $script:temaActual = $tema
    $script:sinAnimaciones = ((Animaciones-Modo) -eq 'Ninguna')
    # Onda de los botones principales: solo con animaciones Normales (transparente en el resto)
    $colOnda = $(if ((Animaciones-Modo) -eq 'Normales') { [System.Windows.Media.Colors]::White } else { [System.Windows.Media.Colors]::Transparent })
    $pincelOnda = New-Object System.Windows.Media.SolidColorBrush($colOnda)
    $app.Resources['T_onda'] = $pincelOnda.psobject.BaseObject
    # Borde de las tarjetas de Ajustes (ficha 25): con «Ninguna» cambia de golpe; con las demás se funde
    $app.Resources['Anim_VerFundido'] = $(if ($script:sinAnimaciones) { [System.Windows.Visibility]::Collapsed } else { [System.Windows.Visibility]::Visible })
    $app.Resources['Anim_VerInstante'] = $(if ($script:sinAnimaciones) { [System.Windows.Visibility]::Visible } else { [System.Windows.Visibility]::Collapsed })
    try { Colores-Rayos } catch {}
}

function Hex-Tema([string]$hex) {
    # Un color claro puesto desde el código, traducido al tema actual (los que no tienen equivalente se quedan)
    $n = $script:HexANombre[$hex.TrimStart('#').ToUpper()]
    if (-not $n) { return $hex }
    return (Valor-Paleta $n $(if ($script:temaActual -eq 'oscuro') { 1 } else { 0 }))
}

function Animaciones-Modo {
    # Normales, Reducidas o Ninguna. El modo sobrio es como Reducidas (solo fundidos), salvo que se haya elegido Ninguna;
    # si Windows las tiene desactivadas y no se ha elegido nada, empieza en Ninguna
    if ([bool]$Config.Sobrio) { return $(if ([string]$Config.Animaciones -eq 'Ninguna') { 'Ninguna' } else { 'Reducidas' }) }
    $m = [string]$Config.Animaciones
    if ($m -in @('Normales', 'Reducidas', 'Ninguna')) { return $m }
    if (-not [System.Windows.SystemParameters]::ClientAreaAnimation) { return 'Ninguna' }
    return 'Normales'
}
