// Tipos de la interfaz nueva de Full Cowl: las tarjetas de Mis maquinas y del Laboratorio, y
// llamadas a Windows. Lo compila ventana-nueva.ps1 una vez (queda en %TEMP%\FullCowl).
// Compatible con C# 5 (Windows PowerShell 5.1).
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
namespace FullCowlWpf {
    // Una tarjeta de la lista de Mis maquinas. El estado y el progreso avisan al cambiar,
    // para que la tarjeta se actualice sola cada pocos segundos.
    public class Maquina : INotifyPropertyChanged {
        public event PropertyChangedEventHandler PropertyChanged;
        private void Avisar(string p) { PropertyChangedEventHandler h = PropertyChanged; if (h != null) h(this, new PropertyChangedEventArgs(p)); }
        public object Datos { get; set; }
        public string Vmx { get; set; }
        public string Nombre { get; set; }
        public string Familia { get; set; }
        public string Base { get; set; }
        public string Tipo { get; set; }
        public string Red { get; set; }
        public string IP { get; set; }
        public string Dominio { get; set; }
        public string Carpeta { get; set; }
        public bool Encendida { get; set; }
        public bool EsBase { get; set; }
        public bool EsDesechable { get; set; }
        public bool EsFc { get; set; }   // máquina creada con Full Cowl (sale la etiqueta «FC»)
        // Etiquetas y nota (ficha 18)
        public string[] Etiquetas { get; set; }     // las guardadas en su .vmx (sin la «Lab …», que se calcula)
        public string EtiquetaLab { get; set; }     // «Lab LAB1» si es de un laboratorio, o vacío
        public string[] EtqVisibles { get; set; }   // las que salen en la tarjeta: como mucho 2 y un «+N»
        public string EtqTodo { get; set; }         // todas las etiquetas y la nota en un texto (para buscar)
        public string Nota { get; set; }
        public bool TieneNota { get; set; }
        public bool TieneEtqONota { get; set; }
        // Acciones rápidas (ficha 19)
        public string Conexion { get; set; }        // rdp, ssh o ninguna
        public bool PuedeCopiarIp { get; set; }
        public string ModoRapidos { get; set; }     // Fundido, Instante (animaciones «Ninguna») o Fijo (pantalla táctil): ver ItemMaq
        public string AyudaIp { get; set; }
        public bool PuedeConectar { get; set; }
        public string AyudaConectar { get; set; }
        private bool trabajando; public bool Trabajando { get { return trabajando; } set { trabajando = value; Avisar("Trabajando"); } }   // encendiendo o apagando (ruedecita)
        public double Tamano { get; set; }
        public string TamanoTexto { get; set; }
        public string Linea { get; set; }
        public string LineaCorta { get; set; }
        public string Ram { get; set; }
        public string IconoGlifo { get; set; }
        public string IconoFondo { get; set; }
        public object IconoLogo { get; set; }
        public object IconoSimbolo { get; set; }
        private string estadoTexto; public string EstadoTexto { get { return estadoTexto; } set { estadoTexto = value; Avisar("EstadoTexto"); } }
        private string estadoColor; public string EstadoColor { get { return estadoColor; } set { estadoColor = value; Avisar("EstadoColor"); } }
        private string estadoFondo; public string EstadoFondo { get { return estadoFondo; } set { estadoFondo = value; Avisar("EstadoFondo"); } }
        private double progreso; public double Progreso { get { return progreso; } set { progreso = value; Avisar("Progreso"); } }
        private bool configurando; public bool Configurando { get { return configurando; } set { configurando = value; Avisar("Configurando"); } }
    }
    // Una maquina de la lista del laboratorio que se esta preparando (aun no existe)
    public class FilaLab {
        public object Datos { get; set; }
        public string Nombre { get; set; }
        public string Detalle { get; set; }
        public string IconoGlifo { get; set; }
        public string IconoFondo { get; set; }
        public object IconoLogo { get; set; }
        public object IconoSimbolo { get; set; }
        public string PapelTexto { get; set; }
        public string PapelColor { get; set; }
        public string PapelFondo { get; set; }
        public string Ip { get; set; }
    }
    public static class Nativo {
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("shell32.dll", CharSet = CharSet.Unicode)] public static extern int SetCurrentProcessExplicitAppUserModelID(string id);
        [DllImport("dwmapi.dll")] public static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);
    }
}
