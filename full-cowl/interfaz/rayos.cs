// Rayos (compartido). Lo usan dos cosas:
//   - la animacion de inicio (inicio.cs), que corre en su propio hilo, y
//   - los rayos ocasionales de la pantalla Inicio (RayosSueltos, abajo), en el hilo normal de la ventana.
// Si la animacion de inicio se desactiva, los rayos de Inicio no dependen de ella (y al reves, solo
// comparten este dibujo).
// Compatible con C# 5 (el compilador de Windows PowerShell 5.1): nada de $"", ?., =>, etc.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Threading;

namespace FullCowlWpf
{
    public class Rayo
    {
        public Point A;
        public Point B;
        public List<Point> Puntos;
        public double Nace;
        public double Vida;
        public double Fuerza;
        public double Proximo;
        public double Desvio;
    }

    public class Chispa
    {
        public Point P;
        public Vector V;
        public double Nace;
        public double Vida;
        public double R;
    }

    // Capa que dibuja rayos, chispas y el aro que se traza al principio (todo en un solo OnRender)
    public class CapaRayos : FrameworkElement
    {
        public List<Rayo> Rayos = new List<Rayo>();
        public List<Chispa> Chispas = new List<Chispa>();
        public double Ahora;
        public Point CentroAro;
        public double RadioAro;
        public double ProgresoAro;
        public double OpacidadAro;
        Random azar;
        Pen pFuera, pMedio, pNucleo;
        Brush brillo, nucleo;

        // Colores del dibujo (por defecto, los de la animacion de inicio)
        public void PonerColores(Color halo, Color medio, Color claro)
        {
            PonerColores(halo, medio, claro, 1.0);
        }

        // grosor: 1 = como la animacion de inicio; menos de 1 = trazos mas finos (rayos pequenos de la barra de progreso)
        public void PonerColores(Color halo, Color medio, Color claro, double grosor)
        {
            pFuera = Pluma(Color.FromArgb(50, halo.R, halo.G, halo.B), 8.0 * grosor);
            pMedio = Pluma(Color.FromArgb(150, medio.R, medio.G, medio.B), 3.4 * grosor);
            pNucleo = Pluma(Color.FromArgb(255, claro.R, claro.G, claro.B), Math.Max(0.8, 1.3 * grosor));
            RadialGradientBrush g = new RadialGradientBrush();
            g.GradientStops.Add(new GradientStop(Color.FromArgb(200, medio.R, medio.G, medio.B), 0.0));
            g.GradientStops.Add(new GradientStop(Color.FromArgb(70, halo.R, halo.G, halo.B), 0.45));
            g.GradientStops.Add(new GradientStop(Color.FromArgb(0, halo.R, halo.G, halo.B), 1.0));
            g.Freeze();
            brillo = g;
            SolidColorBrush n = new SolidColorBrush(claro);
            n.Freeze();
            nucleo = n;
            InvalidateVisual();
        }

        public CapaRayos(Random r)
        {
            azar = r;
            IsHitTestVisible = false;
            pFuera = Pluma(Color.FromArgb(50, 0x2A, 0x9D, 0x8F), 8.0);
            pMedio = Pluma(Color.FromArgb(150, 0x78, 0xEB, 0xDD), 3.4);
            pNucleo = Pluma(Color.FromArgb(255, 0xE8, 0xFF, 0xFA), 1.3);
            RadialGradientBrush g = new RadialGradientBrush();
            g.GradientStops.Add(new GradientStop(Color.FromArgb(200, 0x9F, 0xF5, 0xE8), 0.0));
            g.GradientStops.Add(new GradientStop(Color.FromArgb(70, 0x2A, 0x9D, 0x8F), 0.45));
            g.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0x2A, 0x9D, 0x8F), 1.0));
            g.Freeze();
            brillo = g;
            SolidColorBrush n = new SolidColorBrush(Color.FromRgb(0xF2, 0xFF, 0xFC));
            n.Freeze();
            nucleo = n;
        }

        static Pen Pluma(Color c, double grosor)
        {
            SolidColorBrush b = new SolidColorBrush(c);
            b.Freeze();
            Pen p = new Pen(b, grosor);
            p.StartLineCap = PenLineCap.Round;
            p.EndLineCap = PenLineCap.Round;
            p.LineJoin = PenLineJoin.Round;
            p.Freeze();
            return p;
        }

        protected override void OnRender(DrawingContext dc)
        {
            // Aro que se dibuja solo, como trazado por un rayo
            if (OpacidadAro > 0.01 && ProgresoAro > 0.001)
            {
                double a0 = -Math.PI / 2;
                double barrido = Math.Min(ProgresoAro, 0.9999) * 2 * Math.PI;
                Point ini = new Point(CentroAro.X + RadioAro * Math.Cos(a0), CentroAro.Y + RadioAro * Math.Sin(a0));
                Point fin = new Point(CentroAro.X + RadioAro * Math.Cos(a0 + barrido), CentroAro.Y + RadioAro * Math.Sin(a0 + barrido));
                StreamGeometry arco = new StreamGeometry();
                using (StreamGeometryContext ctx = arco.Open())
                {
                    ctx.BeginFigure(ini, false, false);
                    ctx.ArcTo(fin, new Size(RadioAro, RadioAro), 0, barrido > Math.PI, SweepDirection.Clockwise, true, false);
                }
                arco.Freeze();
                dc.PushOpacity(OpacidadAro);
                dc.DrawGeometry(null, pFuera, arco);
                dc.DrawGeometry(null, pMedio, arco);
                dc.DrawGeometry(null, pNucleo, arco);
                if (ProgresoAro < 0.999)
                {
                    dc.DrawEllipse(brillo, null, fin, 14, 14);
                    dc.DrawEllipse(nucleo, null, fin, 2.2, 2.2);
                }
                dc.Pop();
            }
            // Rayos: tres trazos (halo, color y nucleo claro) y un parpadeo al azar
            foreach (Rayo r in Rayos)
            {
                if (r.Puntos == null || r.Puntos.Count < 2) continue;
                double f = (Ahora - r.Nace) / r.Vida;
                if (f < 0 || f >= 1) continue;
                double alfa = (1 - f * f) * (0.6 + 0.4 * azar.NextDouble()) * r.Fuerza;
                if (alfa <= 0.02) continue;
                StreamGeometry g = new StreamGeometry();
                using (StreamGeometryContext ctx = g.Open())
                {
                    ctx.BeginFigure(r.Puntos[0], false, false);
                    ctx.PolyLineTo(r.Puntos.GetRange(1, r.Puntos.Count - 1), true, true);
                }
                g.Freeze();
                dc.PushOpacity(Math.Min(1.0, alfa));
                dc.DrawGeometry(null, pFuera, g);
                dc.DrawGeometry(null, pMedio, g);
                dc.DrawGeometry(null, pNucleo, g);
                dc.Pop();
            }
            // Chispas sueltas que salen despedidas
            foreach (Chispa c in Chispas)
            {
                double f = (Ahora - c.Nace) / c.Vida;
                if (f < 0 || f >= 1) continue;
                dc.PushOpacity(1 - f);
                dc.DrawEllipse(brillo, null, c.P, c.R * 3.4, c.R * 3.4);
                dc.DrawEllipse(nucleo, null, c.P, c.R * 0.7, c.R * 0.7);
                dc.Pop();
            }
        }
    }

    public static class Trazo
    {
        // Linea quebrada entre dos puntos, como un rayo (cada nivel parte los tramos por la mitad y los desvia)
        public static List<Point> Zigzag(Point a, Point b, double desvio, Random azar)
        {
            List<Point> pts = new List<Point>();
            pts.Add(a); pts.Add(b);
            double d = desvio;
            for (int nivel = 0; nivel < 4; nivel++)
            {
                List<Point> nuevos = new List<Point>();
                for (int i = 0; i < pts.Count - 1; i++)
                {
                    Point p = pts[i], q = pts[i + 1];
                    Vector v = q - p;
                    Vector n = new Vector(-v.Y, v.X);
                    if (n.Length > 0) n.Normalize();
                    Point m = new Point((p.X + q.X) / 2, (p.Y + q.Y) / 2) + n * (-d + azar.NextDouble() * 2 * d);
                    nuevos.Add(p); nuevos.Add(m);
                }
                nuevos.Add(pts[pts.Count - 1]);
                pts = nuevos;
                d *= 0.55;
            }
            return pts;
        }
    }

    // =====================================================================================
    // Rayos ocasionales de la pantalla Inicio. TODOS los valores a ajustar estan aqui.
    // =====================================================================================
    public static class AjusteRayos
    {
        public const double PrimeroMin = 4, PrimeroMax = 8;      // s hasta el primer rayo al entrar en Inicio
        public const double EntreMin = 6, EntreMax = 18;         // s entre un rayo y el siguiente
        public const double VidaMin = 0.15, VidaMax = 0.25;      // s que dura el rayo principal
        public const int RayosMin = 4, RayosMax = 8;             // rayos por evento, repartidos por toda la tarjeta y escalonados en el tiempo
        public const double Escalonado = 1.6;                    // s en los que se reparten los rayos de un evento
        public const double ProbRama = 0.45;                     // probabilidad de que un rayo tenga una rama
        public const int ChispasMin = 1, ChispasMax = 4;
        public const double ChispaVidaMin = 0.3, ChispaVidaMax = 0.9;
        public const double OpacidadMin = 0.60, OpacidadMax = 0.90;   // fuerza maxima del rayo
        public const double LargoMin = 35, LargoMax = 95;        // en unidades del logo de 256
        public const double CicloZigzag = 0.035;                 // cada cuanto tiembla el dibujo (s)
    }

    // Capa transparente con rayos que nacen en el borde del aro del logo de la tarjeta de bienvenida.
    // Sin rayos en marcha no hay ningun temporizador de dibujo: solo uno que despierta al proximo rayo.
    public class RayosSueltos
    {
        readonly Border host;
        readonly Window ventana;
        readonly CapaRayos capa;
        readonly Random azar = new Random();
        readonly Stopwatch reloj = Stopwatch.StartNew();
        readonly DispatcherTimer espera = new DispatcherTimer();
        // Aro del logo en la tarjeta: centro y radio en unidades de la imagen de 256, y la imagen en pantalla
        public Point AroCentro = new Point(125.0, 134.2);
        public double AroRadio = 116.5;
        public FrameworkElement Marca;      // la imagen del logo de fondo (para saber donde esta el aro)
        bool permitido = true;              // la casilla de Ajustes
        bool soltado;                       // ya se llamo a Soltar(): no reacciona a nada mas
        bool corriendo;                     // hay un rayo dibujandose
        bool programado;                    // el temporizador de espera esta puesto
        bool primero = true;                // la proxima espera es la del primer rayo tras entrar en Inicio
        double ultimo;
        // Modo «aro» (asistente de primer arranque): goteo continuo de rayos que salen del aro del logo y, cada 6-11 s,
        // una rafaga de 3 rayos fuertes
        public bool ModoAro;
        // Modo «barra» (al terminar bien una tarea): goteo continuo de rayitos cortos y finos que salen del contorno de esta
        // barra, como si la barra rebosara energia. Mientras sea visible y la ventana este activa.
        public FrameworkElement Barra;
        double proxRafaga;
        bool goteo = true;                  // false: no se programan mas rayos (el Chispazo final sigue funcionando)

        public RayosSueltos(Border contenedor, Window duena)
        {
            host = contenedor;
            ventana = duena;
            capa = new CapaRayos(azar);
            capa.Opacity = 1.0;
            host.Child = capa;
            host.IsHitTestVisible = false;
            espera.Tick += AlCumplirEspera;
            host.IsVisibleChanged += AlCambiarVisible;
            ventana.StateChanged += AlCambiarVentana;
            ventana.Activated += AlCambiarVentana;
            ventana.Deactivated += AlCambiarVentana;
        }

        // Los avisos van a metodos con nombre (no anonimos) para poder quitarlos en Soltar()
        void AlCumplirEspera(object s, EventArgs e) { espera.Stop(); programado = false; if (!soltado) Disparar(); }
        void AlCambiarVisible(object s, DependencyPropertyChangedEventArgs e) { Reevaluar(); }
        void AlCambiarVentana(object s, EventArgs e) { Reevaluar(); }

        // Cuando se quita la fila que llevaba estos rayos: se desapunta de la ventana (si no, la ventana lo seguiria
        // sujetando hasta cerrar Full Cowl), para el reloj y deja de dibujar. Llamarlo dos veces no hace nada.
        // Solo para los rayos de las barras: los de Inicio y los del asistente viven lo que la ventana.
        public void Soltar()
        {
            if (soltado) return;
            soltado = true;
            permitido = false;
            goteo = false;
            espera.Stop(); programado = false;
            espera.Tick -= AlCumplirEspera;
            host.IsVisibleChanged -= AlCambiarVisible;
            ventana.StateChanged -= AlCambiarVentana;
            ventana.Activated -= AlCambiarVentana;
            ventana.Deactivated -= AlCambiarVentana;
            Parar();
            if (host.Child == capa) host.Child = null;
        }

        public bool Permitido
        {
            get { return permitido; }
            set { if (soltado) return; permitido = value; Reevaluar(); }
        }

        public bool Goteo
        {
            get { return goteo; }
            set
            {
                goteo = value;
                if (!goteo) { espera.Stop(); programado = false; }
                else Reevaluar();
            }
        }

        public void PonerColores(Color halo, Color medio, Color claro)
        {
            capa.PonerColores(halo, medio, claro);
        }

        public void PonerColores(Color halo, Color medio, Color claro, double grosor)
        {
            capa.PonerColores(halo, medio, claro, grosor);
        }

        double Intervalo(bool primer)
        {
            if (Barra != null) return primer ? Al(0.1, 0.3) : Al(0.3, 0.9);
            if (ModoAro) return primer ? Al(0.3, 0.8) : Al(0.5, 1.3);
            return primer ? Al(AjusteRayos.PrimeroMin, AjusteRayos.PrimeroMax) : Al(AjusteRayos.EntreMin, AjusteRayos.EntreMax);
        }

        bool PuedeHaber()
        {
            if (!permitido) return false;
            if (!SystemParameters.ClientAreaAnimation) return false;
            if (!host.IsVisible) return false;
            if (ventana.WindowState == WindowState.Minimized || !ventana.IsActive) return false;
            return true;
        }

        // Pone en marcha o para segun las condiciones (al volver a ser visible, el primer rayo sale pronto)
        public void Reevaluar()
        {
            if (soltado) return;
            if (PuedeHaber())
            {
                if (goteo && !programado && !corriendo)
                {
                    Programar(Intervalo(primero));
                    primero = false;
                }
            }
            else
            {
                espera.Stop(); programado = false; primero = true;
                Parar();
            }
        }

        void Programar(double segundos)
        {
            espera.Interval = TimeSpan.FromSeconds(segundos);
            espera.Start();
            programado = true;
        }

        double Al(double a, double b) { return a + azar.NextDouble() * (b - a); }

        // Donde esta el aro dentro del contenedor (la imagen de fondo puede estar movida y recortada)
        bool Aro(out Point c, out double escala)
        {
            c = new Point(0, 0); escala = 1;
            if (Marca == null || host.ActualWidth < 10) return false;
            double w = Marca.ActualWidth; if (w < 10) w = Marca.Width;
            if (w < 10) return false;
            escala = w / 256.0;
            Point sup = Marca.TranslatePoint(new Point(0, 0), host);
            c = new Point(sup.X + AroCentro.X * escala, sup.Y + AroCentro.Y * escala);
            return true;
        }

        void Disparar()
        {
            if (!PuedeHaber()) { Reevaluar(); return; }
            if (Barra != null)
            {
                // de 1 a 3 rayitos alrededor de la barra, escalonados en un tercio de segundo
                if (!RayosContorno(Barra, azar.Next(1, 4), 0.3)) { Programar(Intervalo(false)); return; }
                if (!corriendo) { corriendo = true; CompositionTarget.Rendering += Fotograma; }
                return;
            }
            Point c; double escala;
            if (!Aro(out c, out escala)) { Programar(Intervalo(false)); return; }
            double t = reloj.Elapsed.TotalSeconds;
            int n = azar.Next(AjusteRayos.RayosMin, AjusteRayos.RayosMax + 1);
            bool fuerte = false;
            if (ModoAro)
            {
                if (proxRafaga == 0) proxRafaga = t + Al(3, 6);
                if (t >= proxRafaga) { n = 3; fuerte = true; proxRafaga = t + Al(6, 11); }
                else n = 1;
            }
            for (int i = 0; i < n; i++) { if (ModoAro) NuevoAro(t, c, escala, fuerte); else Nuevo(t, c, escala); }
            ultimo = t;
            if (!corriendo)
            {
                corriendo = true;
                CompositionTarget.Rendering += Fotograma;
            }
        }

        // Un rayo que nace en el aro del logo y sale hacia fuera (ficha 16)
        void NuevoAro(double t, Point c, double escala, bool fuerte)
        {
            double ang = Al(0, 2 * Math.PI);
            double radio = AroRadio * escala;
            Point a = new Point(c.X + radio * Math.Cos(ang), c.Y + radio * Math.Sin(ang));
            double dir = ang + Al(-0.65, 0.65);
            double largo = Al(AjusteRayos.LargoMin, AjusteRayos.LargoMax) * escala * (fuerte ? 1.0 : 0.75);
            t += Al(0, fuerte ? 0.25 : 0.0);
            Point b = new Point(a.X + largo * Math.Cos(dir), a.Y + largo * Math.Sin(dir));
            Rayo r = new Rayo();
            r.A = a; r.B = b; r.Desvio = largo * 0.3;
            r.Puntos = Trazo.Zigzag(a, b, r.Desvio, azar);
            r.Nace = t; r.Vida = Al(AjusteRayos.VidaMin, AjusteRayos.VidaMax);
            r.Fuerza = fuerte ? Al(0.8, 1.0) : Al(AjusteRayos.OpacidadMin, AjusteRayos.OpacidadMax) * 0.8;
            r.Proximo = t + AjusteRayos.CicloZigzag;
            capa.Rayos.Add(r);
            if (azar.NextDouble() < AjusteRayos.ProbRama)
            {
                Point m = r.Puntos[r.Puntos.Count / 2];
                double dir2 = dir + (azar.NextDouble() < 0.5 ? -1 : 1) * Al(0.4, 0.8);
                double largo2 = largo * Al(0.3, 0.5);
                Rayo r2 = new Rayo();
                r2.A = m; r2.B = new Point(m.X + largo2 * Math.Cos(dir2), m.Y + largo2 * Math.Sin(dir2));
                r2.Desvio = largo2 * 0.3;
                r2.Puntos = Trazo.Zigzag(r2.A, r2.B, r2.Desvio, azar);
                r2.Nace = t; r2.Vida = r.Vida * 0.8; r2.Fuerza = r.Fuerza * 0.8; r2.Proximo = t + AjusteRayos.CicloZigzag;
                capa.Rayos.Add(r2);
            }
            int nCh = azar.Next(AjusteRayos.ChispasMin, AjusteRayos.ChispasMax + 1);
            for (int i = 0; i < nCh; i++)
            {
                Chispa ch = new Chispa();
                ch.P = b;
                double va = dir + Al(-0.5, 0.5);
                double vel = Al(15, 45) * escala;
                ch.V = new Vector(vel * Math.Cos(va), vel * Math.Sin(va));
                ch.Nace = t; ch.Vida = Al(AjusteRayos.ChispaVidaMin, AjusteRayos.ChispaVidaMax); ch.R = Al(0.8, 1.5);
                capa.Chispas.Add(ch);
            }
        }

        void Nuevo(double t, Point c, double escala)
        {
            // Nacen en cualquier punto de la tarjeta (no solo en el aro), cada uno en su momento
            double w = host.ActualWidth, h = host.ActualHeight;
            if (w < 40 || h < 40) return;
            Point a = new Point(Al(12, w - 12), Al(12, h - 12));
            double ang = Al(0, 2 * Math.PI);
            t += Al(0, AjusteRayos.Escalonado);
            double dir = ang;
            double largo = Al(AjusteRayos.LargoMin, AjusteRayos.LargoMax) * escala;
            Point b = new Point(a.X + largo * Math.Cos(dir), a.Y + largo * Math.Sin(dir));
            Rayo r = new Rayo();
            r.A = a; r.B = b; r.Desvio = largo * 0.3;
            r.Puntos = Trazo.Zigzag(a, b, r.Desvio, azar);
            r.Nace = t; r.Vida = Al(AjusteRayos.VidaMin, AjusteRayos.VidaMax);
            r.Fuerza = Al(AjusteRayos.OpacidadMin, AjusteRayos.OpacidadMax);
            r.Proximo = t + AjusteRayos.CicloZigzag;
            capa.Rayos.Add(r);
            if (azar.NextDouble() < AjusteRayos.ProbRama)
            {
                // Una rama que sale de la mitad del rayo
                Point m = r.Puntos[r.Puntos.Count / 2];
                double dir2 = dir + (azar.NextDouble() < 0.5 ? -1 : 1) * Al(0.4, 0.8);
                double largo2 = largo * Al(0.3, 0.5);
                Rayo r2 = new Rayo();
                r2.A = m; r2.B = new Point(m.X + largo2 * Math.Cos(dir2), m.Y + largo2 * Math.Sin(dir2));
                r2.Desvio = largo2 * 0.3;
                r2.Puntos = Trazo.Zigzag(r2.A, r2.B, r2.Desvio, azar);
                r2.Nace = t; r2.Vida = r.Vida * 0.8; r2.Fuerza = r.Fuerza * 0.8; r2.Proximo = t + AjusteRayos.CicloZigzag;
                capa.Rayos.Add(r2);
            }
            int nCh = azar.Next(AjusteRayos.ChispasMin, AjusteRayos.ChispasMax + 1);
            for (int i = 0; i < nCh; i++)
            {
                Chispa ch = new Chispa();
                ch.P = b;
                double va = dir + Al(-0.5, 0.5);
                double vel = Al(15, 45) * escala;
                ch.V = new Vector(vel * Math.Cos(va), vel * Math.Sin(va));
                ch.Nace = t; ch.Vida = Al(AjusteRayos.ChispaVidaMin, AjusteRayos.ChispaVidaMax); ch.R = Al(0.8, 1.5);
                capa.Chispas.Add(ch);
            }
        }

        // Un solo rayo suave y una o dos chispas junto a un elemento (al terminar una tarea larga).
        // No hace nada si los rayos no estan permitidos, si Inicio no se ve o si la ventana no esta a la vista.
        public bool Chispazo(FrameworkElement ancla)
        {
            if (ancla == null || !PuedeHaber()) return false;
            if (!ancla.IsVisible || host.ActualWidth < 40 || host.ActualHeight < 40) return false;
            Point c = ancla.TranslatePoint(new Point(26, 26), host);
            double t = reloj.Elapsed.TotalSeconds;
            double ang = Al(-Math.PI * 0.9, -Math.PI * 0.1);
            double largo = Al(45, 70);
            Point b = new Point(c.X + largo * Math.Cos(ang), c.Y + largo * Math.Sin(ang));
            Rayo r = new Rayo();
            r.A = c; r.B = b; r.Desvio = largo * 0.3;
            r.Puntos = Trazo.Zigzag(c, b, r.Desvio, azar);
            r.Nace = t; r.Vida = Al(0.25, 0.4); r.Fuerza = Al(0.35, 0.6);
            r.Proximo = t + AjusteRayos.CicloZigzag;
            capa.Rayos.Add(r);
            int nCh = azar.Next(1, 3);
            for (int i = 0; i < nCh; i++)
            {
                Chispa ch = new Chispa();
                ch.P = b;
                double va = ang + Al(-0.6, 0.6);
                double vel = Al(15, 40);
                ch.V = new Vector(vel * Math.Cos(va), vel * Math.Sin(va));
                ch.Nace = t; ch.Vida = Al(0.3, 0.6); ch.R = Al(0.8, 1.4);
                capa.Chispas.Add(ch);
            }
            ultimo = t;
            if (!corriendo) { corriendo = true; CompositionTarget.Rendering += Fotograma; }
            return true;
        }

        // Rayos pequenos y sutiles que salen del contorno de una barra (al terminar bien una tarea: Crear base, Nueva maquina).
        // Solo alrededor de la barra: nacen en su borde y salen hacia fuera, cortos, escalonados en medio segundo.
        public bool Contorno(FrameworkElement barra)
        {
            if (barra == null || !permitido || !SystemParameters.ClientAreaAnimation) return false;
            if (ventana.WindowState == WindowState.Minimized) return false;
            if (!RayosContorno(barra, azar.Next(7, 12), 0.55)) return false;
            if (!corriendo) { corriendo = true; CompositionTarget.Rendering += Fotograma; }
            return true;
        }

        bool RayosContorno(FrameworkElement barra, int n, double escalonado)
        {
            if (barra == null || !host.IsVisible || !barra.IsVisible) return false;
            double w = barra.ActualWidth, h = barra.ActualHeight;
            if (w < 20 || h < 1) return false;
            Point o = barra.TranslatePoint(new Point(0, 0), host);
            double t = reloj.Elapsed.TotalSeconds;
            for (int i = 0; i < n; i++)
            {
                Point a; double dir;
                double lado = azar.NextDouble();
                if (lado < 0.12)
                {
                    // extremo izquierdo
                    a = new Point(o.X, o.Y + h / 2); dir = Math.PI + Al(-0.7, 0.7);
                }
                else if (lado < 0.24)
                {
                    // extremo derecho
                    a = new Point(o.X + w, o.Y + h / 2); dir = Al(-0.7, 0.7);
                }
                else
                {
                    bool arriba = azar.NextDouble() < 0.5;
                    a = new Point(o.X + Al(4, w - 4), arriba ? o.Y : o.Y + h);
                    dir = (arriba ? -Math.PI / 2 : Math.PI / 2) + Al(-0.75, 0.75);
                }
                double largo = Al(8, 18);
                Point fin = new Point(a.X + largo * Math.Cos(dir), a.Y + largo * Math.Sin(dir));
                Rayo r = new Rayo();
                r.A = a; r.B = fin; r.Desvio = largo * 0.35;
                r.Puntos = Trazo.Zigzag(a, fin, r.Desvio, azar);
                r.Nace = t + Al(0, escalonado); r.Vida = Al(0.14, 0.26); r.Fuerza = Al(0.35, 0.6);
                r.Proximo = r.Nace + AjusteRayos.CicloZigzag;
                capa.Rayos.Add(r);
                if (azar.NextDouble() < 0.3)
                {
                    Chispa ch = new Chispa();
                    ch.P = fin;
                    double va = dir + Al(-0.5, 0.5);
                    double vel = Al(10, 26);
                    ch.V = new Vector(vel * Math.Cos(va), vel * Math.Sin(va));
                    ch.Nace = r.Nace; ch.Vida = Al(0.25, 0.5); ch.R = Al(0.5, 0.9);
                    capa.Chispas.Add(ch);
                }
            }
            ultimo = t;
            return true;
        }

        void Fotograma(object sender, EventArgs e)
        {
            double t = reloj.Elapsed.TotalSeconds;
            double dt = Math.Min(0.1, t - ultimo);
            ultimo = t;
            capa.Ahora = t;
            capa.Rayos.RemoveAll(delegate (Rayo r) { return t - r.Nace >= r.Vida; });
            foreach (Rayo r in capa.Rayos)
            {
                if (t >= r.Proximo) { r.Puntos = Trazo.Zigzag(r.A, r.B, r.Desvio, azar); r.Proximo = t + AjusteRayos.CicloZigzag; }
            }
            capa.Chispas.RemoveAll(delegate (Chispa c) { return t - c.Nace >= c.Vida; });
            foreach (Chispa c in capa.Chispas)
            {
                if (t < c.Nace) continue;
                c.P = c.P + c.V * dt;
                c.V = c.V * Math.Pow(0.2, dt);
            }
            capa.InvalidateVisual();
            if (capa.Rayos.Count == 0 && capa.Chispas.Count == 0)
            {
                // Se acabo: se suelta el dibujo (nada gasta procesador) y se programa el siguiente
                Parar();
                if (PuedeHaber() && goteo) Programar(Intervalo(false));
            }
        }

        void Parar()
        {
            if (corriendo) { CompositionTarget.Rendering -= Fotograma; corriendo = false; }
            capa.Rayos.Clear(); capa.Chispas.Clear();
            capa.InvalidateVisual();
        }
    }
}
