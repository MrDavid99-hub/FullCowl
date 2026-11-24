// Animacion de inicio de la interfaz nueva de Full Cowl.
// El logo (recursos/inicio: disco, F, C y mascara) se monta mientras se acerca, con rayos
// electricos verde-azulados alrededor. Va en su propio hilo, asi se mueve fluida mientras la
// ventana principal se carga en el hilo de PowerShell.
//   Empezar(...)  la muestra (no espera)
//   Listo()       la ventana principal ya esta cargada: puede terminar
//   Esperar(ms)   espera a que la animacion acabe (o salte)
//   Cerrar()      la quita (cuando la ventana principal ya se ve)
// Los rayos (Rayo, Chispa, CapaRayos, Trazo) estan en rayos.cs, que se compila antes.
// Compatible con C# 5 (el compilador de Windows PowerShell 5.1): nada de $"", ?., =>, etc.
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using System.Windows.Threading;

namespace FullCowlWpf
{
    public static class Inicio
    {
        [DllImport("dwmapi.dll")]
        static extern int DwmSetWindowAttribute(IntPtr hwnd, int attr, ref int value, int size);

        // Tiempos (segundos)
        const double T_ARO = 0.05, D_ARO = 0.55;
        const double T_DISCO = 0.12, D_DISCO = 0.50;
        const double T_F = 0.40, D_F = 0.50;
        const double T_C = 0.56, D_C = 0.50;
        const double T_MASCARA = 1.00, T_IMPACTO = 1.30;
        const double T_TITULO = 1.45, D_TITULO = 0.50;
        const double T_ESPERA = 2.05;          // a partir de aqui, quieto hasta que la ventana este lista
        const double D_SALIDA = 0.32;
        const double RITMO = 1.22;             // todo el montaje va 1,22 veces mas despacio (unos 2,5 s)

        // Escena (unidades de WPF): ventana de 600x440; el logo (256 px) se ve a 224
        const double ANCHO = 600, ALTO = 440;
        const double CX = 300, CY = 192;
        const double K = 224.0 / 256.0;
        // Centro y radio del aro dentro de la imagen del logo (256 px)
        const double DISCO_X = 125.0, DISCO_Y = 134.2, DISCO_R = 116.5;

        static Thread hilo;
        static volatile bool listo, saltar, cerrar;
        static ManualResetEvent terminado = new ManualResetEvent(false);
        static Dispatcher disp;
        static Window ventana;
        static Stopwatch reloj;
        static double desfase, anterior = -1, tSalida = -1, acumulado;
        static bool impacto, avisado;
        static Random azar = new Random();
        public static string Error = "";

        static Canvas lienzo, grupo;
        static ScaleTransform escalaGrupo;
        static TranslateTransform temblor;
        static Image disco, letraF, letraC, mascara, titulo;
        static Ellipse aura, destello, sombraTitulo;
        static TextBlock cargando;
        static CapaRayos capa;

        public static void Empezar(string carpetaImagenes, string carpetaFuentes)
        {
            if (hilo != null) return;
            // Los rayos estan en otro DLL cargado desde archivo: el hilo de la animacion no lo encuentra por nombre
            // (FileNotFoundException), asi que se le indica cual es entre los ya cargados.
            AppDomain.CurrentDomain.AssemblyResolve += delegate (object remitente, ResolveEventArgs ev)
            {
                foreach (System.Reflection.Assembly ens in AppDomain.CurrentDomain.GetAssemblies())
                    if (ens.FullName == ev.Name || ens.GetName().Name == new System.Reflection.AssemblyName(ev.Name).Name) return ens;
                return null;
            };
            hilo = new Thread(delegate ()
            {
                try { Correr(carpetaImagenes, carpetaFuentes); }
                catch (Exception ex) { Error = ex.ToString(); }
                finally { terminado.Set(); }
            });
            hilo.SetApartmentState(ApartmentState.STA);
            hilo.IsBackground = true;
            hilo.Start();
        }

        public static void Listo() { listo = true; }

        public static bool Esperar(int milisegundos)
        {
            if (hilo == null) return true;
            return terminado.WaitOne(milisegundos);
        }

        [DllImport("user32.dll")] static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] static extern uint GetWindowThreadProcessId(IntPtr hwnd, IntPtr pid);
        [DllImport("kernel32.dll")] static extern uint GetCurrentThreadId();
        [DllImport("user32.dll")] static extern bool AttachThreadInput(uint desde, uint hacia, bool unir);
        [DllImport("user32.dll")] static extern bool SetForegroundWindow(IntPtr hwnd);
        [DllImport("user32.dll")] static extern bool BringWindowToTop(IntPtr hwnd);

        // Llamar desde el hilo de la ventana principal cuando ya se ve: la pone delante (mientras esta
        // animacion aun tiene el primer plano, asi Windows lo permite) y luego quita la animacion.
        // Si se cerrase antes, Windows daria el primer plano a la ventana de detras (el Explorador).
        public static void DarPaso(IntPtr principal)
        {
            try
            {
                IntPtr delante = GetForegroundWindow();
                uint suHilo = GetWindowThreadProcessId(delante, IntPtr.Zero);
                uint yo = GetCurrentThreadId();
                bool unido = suHilo != 0 && suHilo != yo && AttachThreadInput(yo, suHilo, true);
                BringWindowToTop(principal);
                SetForegroundWindow(principal);
                if (unido) AttachThreadInput(yo, suHilo, false);
            }
            catch { }
            Cerrar();
        }

        public static void Cerrar()
        {
            cerrar = true;
            Dispatcher d = disp;
            if (d == null) return;
            try
            {
                d.BeginInvoke(new Action(delegate ()
                {
                    try { CompositionTarget.Rendering -= Fotograma; } catch { }
                    try { if (ventana != null) ventana.Close(); } catch { }
                    d.InvokeShutdown();
                }));
            }
            catch { }
        }

        static BitmapImage Cargar(string ruta)
        {
            BitmapImage b = new BitmapImage();
            b.BeginInit();
            b.UriSource = new Uri(ruta);
            b.CacheOption = BitmapCacheOption.OnLoad;
            b.EndInit();
            b.Freeze();
            return b;
        }

        static Image Pieza(string carpeta, string archivo, double pivX, double pivY)
        {
            Image i = new Image();
            i.Source = Cargar(System.IO.Path.Combine(carpeta, archivo));
            i.Width = 256; i.Height = 256;
            i.Stretch = Stretch.Fill;
            RenderOptions.SetBitmapScalingMode(i, BitmapScalingMode.HighQuality);
            i.RenderTransformOrigin = new Point(pivX / 256.0, pivY / 256.0);
            TransformGroup tg = new TransformGroup();
            tg.Children.Add(new ScaleTransform(1, 1));
            tg.Children.Add(new RotateTransform(0));
            tg.Children.Add(new TranslateTransform(0, 0));
            i.RenderTransform = tg;
            i.Opacity = 0;
            grupo.Children.Add(i);
            return i;
        }

        static void Poner(Image i, double escala, double angulo, double x, double y, double opacidad)
        {
            TransformGroup tg = (TransformGroup)i.RenderTransform;
            ScaleTransform s = (ScaleTransform)tg.Children[0];
            s.ScaleX = escala; s.ScaleY = escala;
            ((RotateTransform)tg.Children[1]).Angle = angulo;
            TranslateTransform t = (TranslateTransform)tg.Children[2];
            t.X = x; t.Y = y;
            i.Opacity = opacidad;
        }

        static void Correr(string img, string fuentes)
        {
            disp = Dispatcher.CurrentDispatcher;
            if (cerrar) return;

            ventana = new Window();
            ventana.Title = "Full Cowl";
            ventana.WindowStyle = WindowStyle.None;
            ventana.ResizeMode = ResizeMode.NoResize;
            ventana.Width = ANCHO; ventana.Height = ALTO;
            ventana.WindowStartupLocation = WindowStartupLocation.CenterScreen;
            ventana.Topmost = true;
            ventana.ShowInTaskbar = true;
            ventana.UseLayoutRounding = true;
            RadialGradientBrush fondo = new RadialGradientBrush();
            fondo.GradientOrigin = new Point(0.5, 0.42);
            fondo.Center = new Point(0.5, 0.42);
            fondo.RadiusX = 0.75; fondo.RadiusY = 0.85;
            fondo.GradientStops.Add(new GradientStop(Color.FromRgb(0x1F, 0x4B, 0x2E), 0.0));
            fondo.GradientStops.Add(new GradientStop(Color.FromRgb(0x12, 0x26, 0x1A), 0.55));
            fondo.GradientStops.Add(new GradientStop(Color.FromRgb(0x08, 0x14, 0x0D), 1.0));
            fondo.Freeze();
            ventana.Background = fondo;
            try
            {
                ventana.Icon = BitmapFrame.Create(new Uri(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(img), "full-cowl-icono-2.ico")));
            }
            catch { }

            Grid raiz = new Grid();
            ventana.Content = raiz;
            lienzo = new Canvas();
            lienzo.Width = ANCHO; lienzo.Height = ALTO;
            lienzo.ClipToBounds = true;
            raiz.Children.Add(lienzo);

            // Halo verde detras del logo
            aura = new Ellipse();
            aura.Width = 420; aura.Height = 420;
            RadialGradientBrush ga = new RadialGradientBrush();
            ga.GradientStops.Add(new GradientStop(Color.FromArgb(150, 0x39, 0x82, 0x4D), 0.0));
            ga.GradientStops.Add(new GradientStop(Color.FromArgb(60, 0x2A, 0x9D, 0x8F), 0.45));
            ga.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0x2A, 0x9D, 0x8F), 1.0));
            ga.Freeze();
            aura.Fill = ga;
            aura.IsHitTestVisible = false;
            aura.Opacity = 0;
            Canvas.SetLeft(aura, CX - 210); Canvas.SetTop(aura, CY - 210);
            lienzo.Children.Add(aura);

            // Logo: las cuatro piezas en un mismo marco de 256x256, escalado alrededor de su centro
            grupo = new Canvas();
            grupo.Width = 256; grupo.Height = 256;
            Canvas.SetLeft(grupo, CX - 128); Canvas.SetTop(grupo, CY - 128);
            grupo.RenderTransformOrigin = new Point(0.5, 0.5);
            TransformGroup tgg = new TransformGroup();
            escalaGrupo = new ScaleTransform(K, K);
            temblor = new TranslateTransform(0, 0);
            tgg.Children.Add(escalaGrupo);
            tgg.Children.Add(temblor);
            grupo.RenderTransform = tgg;
            lienzo.Children.Add(grupo);
            disco = Pieza(img, "disco.png", DISCO_X, DISCO_Y);
            letraF = Pieza(img, "f.png", 134, 100);
            letraC = Pieza(img, "c.png", 183.5, 139.5);
            mascara = Pieza(img, "mascara.png", 86, 201);

            // Destello al encajar la mascara
            destello = new Ellipse();
            destello.Width = 340; destello.Height = 340;
            RadialGradientBrush gd = new RadialGradientBrush();
            gd.GradientStops.Add(new GradientStop(Color.FromArgb(255, 0xF2, 0xFF, 0xFC), 0.0));
            gd.GradientStops.Add(new GradientStop(Color.FromArgb(140, 0x78, 0xEB, 0xDD), 0.3));
            gd.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0x2A, 0x9D, 0x8F), 1.0));
            gd.Freeze();
            destello.Fill = gd;
            destello.IsHitTestVisible = false;
            destello.Opacity = 0;
            destello.RenderTransformOrigin = new Point(0.5, 0.5);
            destello.RenderTransform = new ScaleTransform(1, 1);
            // centrado donde encaja la mascara
            Canvas.SetLeft(destello, CX + (86 - 128) * K - 170); Canvas.SetTop(destello, CY + (201 - 128) * K - 170);
            lienzo.Children.Add(destello);

            // Rayos y chispas
            capa = new CapaRayos(azar);
            capa.Width = ANCHO; capa.Height = ALTO;
            lienzo.Children.Add(capa);

            // Titulo (FULL COWL) debajo del logo
            titulo = new Image();
            BitmapImage bt = Cargar(System.IO.Path.Combine(System.IO.Path.GetDirectoryName(img), "titulo.png"));
            titulo.Source = bt;
            titulo.Width = 300;
            titulo.Height = 300.0 * bt.PixelHeight / bt.PixelWidth;
            RenderOptions.SetBitmapScalingMode(titulo, BitmapScalingMode.HighQuality);
            titulo.RenderTransform = new TranslateTransform(0, 18);
            titulo.Opacity = 0;
            Canvas.SetLeft(titulo, CX - 150); Canvas.SetTop(titulo, CY + 130);
            // Sombra suave detras de las letras: el verde de FULL se pierde sobre el fondo verde
            sombraTitulo = new Ellipse();
            sombraTitulo.Width = 360; sombraTitulo.Height = 62;
            RadialGradientBrush gs = new RadialGradientBrush();
            gs.GradientStops.Add(new GradientStop(Color.FromArgb(140, 0x04, 0x0C, 0x07), 0.0));
            gs.GradientStops.Add(new GradientStop(Color.FromArgb(90, 0x04, 0x0C, 0x07), 0.6));
            gs.GradientStops.Add(new GradientStop(Color.FromArgb(0, 0x04, 0x0C, 0x07), 1.0));
            gs.Freeze();
            sombraTitulo.Fill = gs;
            sombraTitulo.IsHitTestVisible = false;
            sombraTitulo.Opacity = 0;
            Canvas.SetLeft(sombraTitulo, CX - 180); Canvas.SetTop(sombraTitulo, CY + 130 + titulo.Height / 2 - 31);
            lienzo.Children.Add(sombraTitulo);
            lienzo.Children.Add(titulo);

            // Solo si la ventana tarda en cargar
            cargando = new TextBlock();
            cargando.Text = "Cargando tus m\u00e1quinas\u2026";
            cargando.FontSize = 12;
            cargando.Foreground = new SolidColorBrush(Color.FromRgb(0x9F, 0xC9, 0xB0));
            try { cargando.FontFamily = new FontFamily(new Uri(fuentes.TrimEnd('\\') + "\\"), "./#Inter, Segoe UI"); } catch { }
            cargando.HorizontalAlignment = HorizontalAlignment.Center;
            cargando.VerticalAlignment = VerticalAlignment.Bottom;
            cargando.Margin = new Thickness(0, 0, 0, 22);
            cargando.Opacity = 0;
            raiz.Children.Add(cargando);

            // Un clic o una tecla la adelantan al final
            ventana.MouseLeftButtonDown += delegate (object s, MouseButtonEventArgs e) { saltar = true; };
            ventana.KeyDown += delegate (object s, KeyEventArgs e) { saltar = true; };
            ventana.SourceInitialized += delegate (object s, EventArgs e)
            {
                try
                {
                    IntPtr h = new WindowInteropHelper(ventana).Handle;
                    int esquinas = 2;
                    DwmSetWindowAttribute(h, 33, ref esquinas, 4);
                    int borde = 0x001A261A;
                    DwmSetWindowAttribute(h, 34, ref borde, 4);
                }
                catch { }
            };

            Fotograma(null, EventArgs.Empty);
            ventana.Show();
            reloj = Stopwatch.StartNew();
            CompositionTarget.Rendering += Fotograma;
            Dispatcher.Run();
        }

        // ---------------------------------------------------------------- utilidades
        static double Limitar(double v) { return v < 0 ? 0 : (v > 1 ? 1 : v); }
        static double SalidaCubica(double p) { double q = 1 - p; return 1 - q * q * q; }
        static double EntradaCubica(double p) { return p * p * p; }
        static double EntradaSalida(double p) { return p < 0.5 ? 4 * p * p * p : 1 - Math.Pow(-2 * p + 2, 3) / 2; }
        static double ConRebote(double p, double fuerza)
        {
            double c3 = fuerza + 1;
            double q = p - 1;
            return 1 + c3 * q * q * q + fuerza * q * q;
        }
        static double Al(double a, double b) { return a + azar.NextDouble() * (b - a); }

        static List<Point> Zigzag(Point a, Point b, double desvio) { return Trazo.Zigzag(a, b, desvio, azar); }

        static Point CentroDisco(double escala)
        {
            return new Point(CX + (DISCO_X - 128) * escala + temblor.X, CY + (DISCO_Y - 128) * escala + temblor.Y);
        }

        static void NuevoRayo(double t, double escala, bool fuerte)
        {
            Point c = CentroDisco(escala);
            double radio = DISCO_R * escala;
            double ang = Al(0, 2 * Math.PI);
            Point a = new Point(c.X + radio * Al(0.97, 1.07) * Math.Cos(ang), c.Y + radio * Al(0.97, 1.07) * Math.Sin(ang));
            double dir = ang + Al(-0.65, 0.65);
            double largo = (fuerte ? Al(45, 100) : Al(20, 58)) * escala / K;
            Point b = new Point(a.X + largo * Math.Cos(dir), a.Y + largo * Math.Sin(dir));
            Rayo r = new Rayo();
            r.A = a; r.B = b; r.Desvio = largo * 0.3;
            r.Puntos = Zigzag(a, b, r.Desvio);
            r.Nace = t; r.Vida = fuerte ? Al(0.14, 0.26) : Al(0.07, 0.16);
            r.Fuerza = fuerte ? 1.0 : Al(0.65, 1.0);
            r.Proximo = t + 0.035;
            capa.Rayos.Add(r);
            // A veces, una rama
            if (azar.NextDouble() < 0.35)
            {
                Point m = r.Puntos[r.Puntos.Count / 2];
                double dir2 = dir + (azar.NextDouble() < 0.5 ? -1 : 1) * Al(0.4, 0.8);
                double largo2 = largo * Al(0.3, 0.5);
                Rayo r2 = new Rayo();
                r2.A = m; r2.B = new Point(m.X + largo2 * Math.Cos(dir2), m.Y + largo2 * Math.Sin(dir2));
                r2.Desvio = largo2 * 0.3;
                r2.Puntos = Zigzag(r2.A, r2.B, r2.Desvio);
                r2.Nace = t; r2.Vida = r.Vida * 0.8; r2.Fuerza = r.Fuerza * 0.8; r2.Proximo = t + 0.035;
                capa.Rayos.Add(r2);
            }
            // Chispas que salen de la punta
            int n = fuerte ? 3 : (azar.NextDouble() < 0.5 ? 1 : 0);
            for (int i = 0; i < n; i++)
            {
                Chispa ch = new Chispa();
                ch.P = b;
                double va = dir + Al(-0.5, 0.5);
                double vel = Al(30, 95);
                ch.V = new Vector(vel * Math.Cos(va), vel * Math.Sin(va));
                ch.Nace = t; ch.Vida = Al(0.35, 0.85); ch.R = Al(1.0, 2.1);
                capa.Chispas.Add(ch);
            }
        }

        // ---------------------------------------------------------------- cada fotograma
        static void Fotograma(object sender, EventArgs e)
        {
            try
            {
                if (cerrar) return;
                // treal: segundos de verdad (vida de los rayos, salida); t: tiempo del montaje (mas lento)
                double treal = reloj == null ? 0 : reloj.Elapsed.TotalSeconds + desfase;
                if (saltar && treal < T_ESPERA * RITMO)
                {
                    desfase += T_ESPERA * RITMO - treal;
                    treal = T_ESPERA * RITMO;
                }
                saltar = false;
                double dt = anterior < 0 ? 0 : Math.Max(0, Math.Min(0.1, treal - anterior));
                anterior = treal;
                double t = treal / RITMO;

                // Salida: en cuanto la ventana principal esta lista (y la animacion ha llegado al final)
                if (tSalida < 0 && listo && t >= T_ESPERA) tSalida = treal;
                double ps = tSalida < 0 ? 0 : Limitar((treal - tSalida) / D_SALIDA);

                // El logo se acerca
                double s = K * (0.72 + 0.28 * SalidaCubica(Limitar(t / 1.55))) * (1 + 0.06 * EntradaCubica(ps));
                escalaGrupo.ScaleX = s; escalaGrupo.ScaleY = s;

                // Temblor al encajar la mascara
                double pt = (t - T_IMPACTO) / 0.24;
                if (pt > 0 && pt < 1)
                {
                    temblor.X = 3.4 * (1 - pt) * Math.Sin(pt * 40);
                    temblor.Y = 2.0 * (1 - pt) * Math.Cos(pt * 34);
                }
                else { temblor.X = 0; temblor.Y = 0; }

                // Disco: aparece girando
                double p = Limitar((t - T_DISCO) / D_DISCO);
                double v = SalidaCubica(p);
                Poner(disco, 0.82 + 0.18 * v, -80 * (1 - v), 0, 0, Limitar(p * 2.2));
                // F: entra por la izquierda
                p = Limitar((t - T_F) / D_F);
                v = ConRebote(p, 1.3);
                Poner(letraF, 1.15 - 0.15 * v, -24 * (1 - v), -160 * (1 - v), -36 * (1 - v), Limitar(p * 3));
                // C: entra por la derecha
                p = Limitar((t - T_C) / D_C);
                v = ConRebote(p, 1.3);
                Poner(letraC, 1.15 - 0.15 * v, 24 * (1 - v), 160 * (1 - v), 28 * (1 - v), Limitar(p * 3));
                // Mascara: cae y encaja de golpe, con un pequeno rebote
                p = Limitar((t - T_MASCARA) / (T_IMPACTO - T_MASCARA));
                v = EntradaCubica(p);
                double rebote = 0;
                double pr = (t - T_IMPACTO) / 0.3;
                if (pr > 0 && pr < 1) rebote = 0.06 * Math.Sin(pr * Math.PI) * (1 - pr);
                Poner(mascara, 1.4 - 0.4 * v + rebote, 10 * (1 - v), -30 * (1 - v), 120 * (1 - v), Limitar(p * 4));

                // Destello y rafaga de rayos al encajar
                if (!impacto && t >= T_IMPACTO)
                {
                    impacto = true;
                    for (int i = 0; i < 16; i++) NuevoRayo(treal, s, true);
                }
                double pd = (t - T_IMPACTO) / 0.42;
                if (pd > 0 && pd < 1)
                {
                    destello.Opacity = 0.7 * (1 - pd) * (1 - pd);
                    ScaleTransform ds = (ScaleTransform)destello.RenderTransform;
                    ds.ScaleX = ds.ScaleY = 0.5 + 0.9 * pd;
                }
                else destello.Opacity = 0;

                // Halo de fondo
                double pulso = (pd > 0 && pd < 1) ? 0.45 * (1 - pd) : 0;
                aura.Opacity = Math.Min(1, 0.15 + 0.4 * Limitar(t / 1.2) + pulso + 0.05 * Math.Sin(treal * 3));

                // Aro trazado al principio
                capa.CentroAro = CentroDisco(s);
                capa.RadioAro = DISCO_R * s + 3;
                capa.ProgresoAro = EntradaSalida(Limitar((t - T_ARO) / D_ARO));
                capa.OpacidadAro = t < T_ARO + D_ARO ? 1 : 1 - Limitar((t - T_ARO - D_ARO) / 0.45);

                // Titulo
                p = Limitar((t - T_TITULO) / D_TITULO);
                titulo.Opacity = p;
                sombraTitulo.Opacity = p;
                ((TranslateTransform)titulo.RenderTransform).Y = 18 * (1 - SalidaCubica(p));

                // "Cargando..." solo si la ventana tarda
                double pc = (!listo && t > T_ESPERA + 0.8) ? Limitar((t - T_ESPERA - 0.8) / 0.6) : 0;
                cargando.Opacity = Math.Min(pc, 1 - ps);

                // Rayos nuevos: muchos mientras se monta, pocos cuando ya esta montado
                double tasa = 0;
                if (t > 0.15 && t < T_IMPACTO) tasa = 16;
                else if (t >= T_IMPACTO && t < 2.2) tasa = 10 - 6 * (t - T_IMPACTO) / (2.2 - T_IMPACTO);
                else if (t >= 2.2) tasa = 3.5;
                if (tSalida >= 0) tasa = 0;
                acumulado += tasa * dt;
                while (acumulado >= 1) { NuevoRayo(treal, s, false); acumulado -= 1; }

                // Rayos vivos: tiemblan (se vuelven a dibujar en zigzag cada pocos ms)
                capa.Ahora = treal;
                capa.Rayos.RemoveAll(delegate (Rayo r) { return treal - r.Nace >= r.Vida; });
                foreach (Rayo r in capa.Rayos)
                {
                    if (treal >= r.Proximo) { r.Puntos = Zigzag(r.A, r.B, r.Desvio); r.Proximo = treal + 0.035; }
                }
                capa.Chispas.RemoveAll(delegate (Chispa c) { return treal - c.Nace >= c.Vida; });
                foreach (Chispa c in capa.Chispas)
                {
                    c.P = c.P + c.V * dt;
                    c.V = c.V * Math.Pow(0.2, dt);
                }
                capa.InvalidateVisual();

                // Final: todo se funde con el fondo. A mitad del fundido se avisa a PowerShell para que vaya
                // mostrando la ventana principal mientras esto termina de fundirse (va en otro hilo)
                lienzo.Opacity = 1 - EntradaCubica(ps);
                if (tSalida >= 0 && ps >= 0.5 && !avisado)
                {
                    avisado = true;
                    terminado.Set();
                }
            }
            catch (Exception ex)
            {
                Error = ex.ToString();
                terminado.Set();
            }
        }
    }
}
