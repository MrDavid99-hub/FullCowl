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
variable "cidata_iso" { type = string }
# Mini-ISO de arranque (recursos/arranque/ubuntu-autoinstall.iso, ficha 26). Si viene, la máquina arranca de ELLA
# y la ISO de Ubuntu va en otro CD: así el instalador no pregunta "Continue with autoinstall? (yes|no)".
# Vacía = como siempre (arranca de la ISO de Ubuntu y hay que escribir "yes").
variable "arranque_iso" {
  type    = string
  default = ""
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
variable "desktop" {
  type    = bool
  default = false
}
variable "cpus" {
  type    = number
  default = 4
}
variable "memory" {
  type    = number
  default = 6144
}
variable "disk_gb" {
  type    = number
  default = 40
}

source "vmware-iso" "ubuntu" {
  # El CD de Packer es el que arranca la máquina: la mini-ISO si la hay; si no, la ISO de Ubuntu
  iso_url      = var.arranque_iso == "" ? var.iso_path : var.arranque_iso
  iso_checksum = "none"

  vm_name          = var.vm_name
  display_name     = var.vm_name
  output_directory = var.output_dir
  guest_os_type    = "ubuntu-64"
  version          = "19"
  # Sin ventana, como Windows: con ventana, "vmrun start ... gui" a veces no vuelve nunca y Packer
  # se queda en "Powering on virtual machine". crear-base.ps1 abre después la VM en VMware para
  # escribir "yes" (o, con la mini-ISO de arranque, para ver cómo va).
  headless         = true
  disable_vnc      = true # Workstation reciente no trae servidor VNC

  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_gb * 1024
  disk_type_id         = "0"
  network              = "nat"
  network_adapter_type = "vmxnet3"
  sound                = var.desktop
  usb                  = true

  communicator           = "ssh"
  ssh_username           = var.username
  ssh_password           = var.password
  ssh_timeout            = "2h"
  ssh_handshake_attempts = 300

  shutdown_command = "echo '${var.password}' | sudo -S shutdown -P now"
  shutdown_timeout = "15m"

  # La configuración de la instalación va en un segundo CD con etiqueta CIDATA
  # (lo genera crear-base.ps1). El instalador de Ubuntu la detecta solo.
  vmx_data = {
    "firmware"           = "bios"
    "sata0.present"      = "TRUE"
    # Con la mini-ISO de arranque, la ISO de Ubuntu va aquí (tiene que seguir conectada: el instalador la busca)
    "sata0:0.present"    = var.arranque_iso == "" ? "FALSE" : "TRUE"
    "sata0:0.deviceType" = "cdrom-image"
    "sata0:0.fileName"   = var.iso_path
    "sata0:1.present"    = "TRUE"
    "sata0:1.deviceType" = "cdrom-image"
    "sata0:1.fileName"   = var.cidata_iso
    # tools_iso: linux.iso de VMware, plan B si open-vm-tools no se puede instalar
    "sata0:3.present"    = var.tools_iso == "" ? "FALSE" : "TRUE"
    "sata0:3.deviceType" = "cdrom-image"
    "sata0:3.fileName"   = var.tools_iso
  }
  # Al terminar se desconectan los CD (los clones usan sata0:2 para su CD de configuración)
  vmx_data_post = {
    "sata0:0.present" = "FALSE"
    "sata0:1.present" = "FALSE"
    "sata0:3.present" = "FALSE"
  }
}

build {
  sources = ["source.vmware-iso.ubuntu"]

  provisioner "shell" {
    # {{ .Vars }}: sin el, Packer NO pasa environment_vars al script (DESKTOP llegaba vacio)
    execute_command  = "echo '${var.password}' | {{ .Vars }} sudo -S -E bash '{{ .Path }}'"
    environment_vars = ["DESKTOP=${var.desktop}"]
    script           = "${path.root}/ubuntu/provision.sh"
  }
}
