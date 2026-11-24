# Laboratorios de ejemplo

Archivos `.fclab` listos para probar. Son **recetas** (qué máquinas, cuánta RAM, qué red), no discos: al importarlos,
Full Cowl usa las bases que tengas en tu PC y te dice cuáles te faltan.

Cómo usarlos: en Full Cowl, **Laboratorio → Crear laboratorio → Plantillas ▾ → Importar…**, o arrastra el archivo a la
ventana. Se abre una pantalla de revisión; al pulsar «Usar esta plantilla» se carga en el creador y tú decides cuándo crearlo.

| Archivo | Qué monta | Bases que necesita |
|---|---|---|
| Dominio con 2 clientes | Controlador de dominio y dos Windows 11 en `empresa.local` | WinServer2022, Win11Pro |
| Servidor web y cliente | Ubuntu con Apache y MariaDB y un Ubuntu con escritorio | Ubuntu2404, Ubuntu2404Desk |
| Kali y objetivo | Kali y un Ubuntu con Apache | Kali, Ubuntu2404 |

No llevan datos personales. Los extras (`apache`, `mariadb`) se instalan solos en el primer arranque de cada máquina.
