# packer/ · plantillas para crear las bases

Una plantilla de Packer (`*.pkr.hcl`) por familia y, en su carpeta, el archivo de instalación desatendida y los scripts
que corren al final: `windows/` (`autounattend`, `sysprep`), `ubuntu/` (autoinstall + `provision.sh`), `debian/` y `kali/`
(preseed), `rhel/` (kickstart, Rocky y AlmaLinux), `arch/`. Los `{{MARCADORES}}` los rellena `crear-base.ps1` con lo
elegido (idioma, teclado, zona, usuario…). La contraseña nunca se escribe en ellos: llega por variable de entorno.
