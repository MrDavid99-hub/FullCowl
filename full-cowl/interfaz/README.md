# interfaz/ · pantallas de Full Cowl (WPF)

Cada pantalla es un `.xaml` (cómo se ve) con su `.ps1` (qué hace): `inicio`, `maquinas`, `nueva`, `bases`, `laboratorio`,
`importar`, `ajustes-hub`, `asistente`… Los `dialogo-*.xaml` son las ventanitas. `estilos.xaml`, `iconos.xaml`, `logos.xaml`
y `tema.ps1` dan el aspecto; `base.ps1` tiene las utilidades comunes. Los `.cs` (rayos, animación de inicio, tipos) se
compilan la primera vez y se guardan en `%TEMP%\FullCowl`.
