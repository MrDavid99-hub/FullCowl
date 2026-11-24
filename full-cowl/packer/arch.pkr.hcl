packer {
  required_plugins {
    vmware = {
      version = ">= 1.1.0"
      source  = "github.com/hashicorp/vmware"
    }
  }
}

variable "iso_path" { type = string }
variable "output_dir" { type = string }
variable "vm_name" { type = string }
variable "http_dir" { type = string }
variable "http_ip" {
  type    = string
  default = "0.0.0.0"
}
variable "tools_iso" {
  type    = string
  default = ""
}
variable "username" { type = string }
variable "password" {
  type      = string
  sensitive = true
}
variable "cpus" {
  type    = number
  default = 4
}
variable "memory" {
  type    = number
  default = 6144
}
variable "desktop" {
  type    = string
  default = "false"
}
variable "disk_gb" {
  type    = number
  default = 60
}

source "vmware-iso" "arch" {
  iso_url      = var.iso_path
  iso_checksum = "none"

  vm_name          = var.vm_name
  display_name     = var.vm_name
  output_directory = var.output_dir
  guest_os_type    = "other5xlinux-64"
  version          = "19"
  # Sin ventana al encender (con ventana, vmrun a veces deja colgado a Packer en «Powering on virtual machine»
  # aunque la VM arranque e incluso se instale). crear-base.ps1 abre la VM en VMware en cuanto está encendida,
  # para poder escribir la línea de arranque.
  headless         = true
  disable_vnc      = true  # Workstation reciente no trae servidor VNC

  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_gb * 1024
  disk_type_id         = "0"
  network              = "nat"
  network_adapter_type = "vmxnet3"
  sound                = true
  usb                  = true

  # El script de instalación (arch.sh, con la contraseña temporal) lo descarga el sistema en vivo de Arch de este servidor web de
  # Packer. Solo escucha en la red NAT de VMware (VMnet8): desde la wifi o la red de clase no se ve.
  http_directory    = var.http_dir
  http_bind_address = var.http_ip
  http_port_min     = 8820
  http_port_max     = 8820

  communicator           = "ssh"
  ssh_username           = var.username
  ssh_password           = var.password
  ssh_timeout            = "1h"
  ssh_handshake_attempts = 300

  shutdown_command = "echo '${var.password}' | sudo -S shutdown -P now"
  shutdown_timeout = "15m"

  vmx_data = {
    "firmware"       = "bios"
    # Disco primero: tras instalar no vuelve a arrancar la ISO
    "bios.bootOrder" = "hdd,cdrom"
    # tools_iso: linux.iso de VMware, plan B si open-vm-tools no se puede instalar
    "sata0.present"      = var.tools_iso == "" ? "FALSE" : "TRUE"
    "sata0:3.present"    = var.tools_iso == "" ? "FALSE" : "TRUE"
    "sata0:3.deviceType" = "cdrom-image"
    "sata0:3.fileName"   = var.tools_iso
  }
  vmx_data_post = {
    "sata0:3.present" = "FALSE"
  }
}

build {
  sources = ["source.vmware-iso.arch"]

  # Utilidades, escritorio opcional y limpieza para clonar (packer/arch/provision.sh)
  provisioner "shell" {
    execute_command  = "echo '${var.password}' | sudo -S -E bash '{{ .Path }}'"
    environment_vars = ["DESKTOP=${var.desktop}"]
    script           = "${path.root}/arch/provision.sh"
  }
}
