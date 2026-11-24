#  «Ficha del laboratorio» (ficha 29): botón en la cabecera de cada laboratorio de «Mis laboratorios» y cuadro con las opciones.
#  El documento lo hace ficha-laboratorio.ps1 (sin tocar las máquinas).

function Abrir-FichaLab {
    $nombreLab = [string]$script:labElegido
    if (-not $nombreLab) { return }
    $e = Nuevo-Dialogo 'dialogo-ficha-lab.xaml' 'Ficha del laboratorio' $nombreLab 560
    $e.FichaTitulo.Text = "Laboratorio $nombreLab"
    $e.FichaAutor.Text = ([string]$Config.Nombre).Trim()
    $e.FichaCarpeta.Text = (Carpeta-FichasLab)   # la de Ajustes → Este PC, o Documentos\Full Cowl\Fichas
    # En formato Texto no hay esquema (es un dibujo)
    $e.OpFichaMd.Add_Checked({ $e.ChkFichaEsquema.IsEnabled = $false })
    $e.OpFichaPdf.Add_Checked({ $e.ChkFichaEsquema.IsEnabled = $true })
    $e.BtnFichaCambiar.Add_Click({ Elegir-Carpeta $e.FichaCarpeta 'Carpeta donde guardar la ficha' $e.Ventana })
    $e.BtnFichaNo.Add_Click({ $e.Ventana.Close() })
    $e.BtnFichaOk.Add_Click({
        $carpetaFicha = $e.FichaCarpeta.Text.Trim()
        if (-not $carpetaFicha) { Mostrar-Toast 'Elige dónde guardar la ficha.' 'info'; return }
        $tituloFicha = $e.FichaTitulo.Text.Trim()
        if (-not $tituloFicha) { $tituloFicha = "Laboratorio $nombreLab" }
        $opciones = [pscustomobject]@{
            Formato = $(if ($e.OpFichaMd.IsChecked) { 'md' } else { 'pdf' })
            Titulo = $tituloFicha; Autor = $e.FichaAutor.Text.Trim(); Carpeta = $carpetaFicha
            Esquema = [bool]$e.ChkFichaEsquema.IsChecked; Usuarios = [bool]$e.ChkFichaUsuarios.IsChecked
            Recursos = [bool]$e.ChkFichaRecursos.IsChecked; Notas = [bool]$e.ChkFichaNotas.IsChecked
        }
        $abrirFicha = [bool]$e.ChkFichaAbrir.IsChecked
        $resFicha = $null
        Iniciar-Espera
        try { $resFicha = Generar-FichaLab $nombreLab $opciones }
        catch { Escribir-Log ("Ficha del laboratorio: " + ($_ | Out-String)); $resFicha = @{ Ok = $false; Aviso = 'No he podido crear la ficha.'; Detalle = $_.Exception.Message; Ruta = '' } }
        finally { Terminar-Espera }
        if (-not $resFicha.Ok) { Error-Amable ([string]$resFicha.Aviso) 'Prueba otra vez o elige otra carpeta.' ([string]$resFicha.Detalle); return }
        $e.Ventana.Close()
        if ($resFicha.Aviso) { Aviso ([string]$resFicha.Aviso) } else { Mostrar-Toast ("Ficha guardada: " + (Split-Path $resFicha.Ruta -Leaf)) }
        if ($abrirFicha -and $resFicha.Ruta) { try { Start-Process -FilePath $resFicha.Ruta } catch { Escribir-Log ("Abrir ficha: " + $_.Exception.Message) } }
    })
    [void]$e.Ventana.ShowDialog()
}
$BtnLmFicha.Add_Click({ Abrir-FichaLab })

