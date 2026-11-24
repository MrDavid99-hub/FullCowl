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
variable "guest_os_type" { type = string }
variable "floppy_dir" { type = string }
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
variable "extra_cd" {
  type    = string
  default = ""
}
variable "tools_iso" {
  type    = string
  default = ""
}
variable "disk_gb" {
  type    = number
  default = 60
}

source "vmware-iso" "windows" {
  iso_url      = var.iso_path
  iso_checksum = "none"

  vm_name          = var.vm_name
  display_name     = var.vm_name
  output_directory = var.output_dir
  guest_os_type    = var.guest_os_type
  version          = "19"
  # En segundo plano: Windows se instala solo y así Packer no depende de la ventana de
  # VMware Workstation (que puede dejarle esperando al encender la VM).
  headless         = true
  disable_vnc      = true # Workstation reciente no trae servidor VNC; Windows no lo necesita

  cpus                 = var.cpus
  memory               = var.memory
  disk_size            = var.disk_gb * 1024
  disk_type_id         = "0"
  disk_adapter_type    = "lsisas1068"
  network              = "nat"
  network_adapter_type = "e1000e"
  sound                = false
  usb                  = true

  floppy_files = [
    "${var.floppy_dir}/autounattend.xml",
    "${var.floppy_dir}/sysprep-oobe.xml",
  ]

  communicator   = "winrm"
  winrm_username = var.username
  winrm_password = var.password
  winrm_timeout  = "3h"
  winrm_use_ssl  = false

  # Generaliza la VM (cada clon tendrá su propio SID). Sysprep se lanza con una tarea
  # programada creada en provision.ps1: si se lanzara por WinRM cortaría la conexión
  # y Packer lo daría por error.
  shutdown_command = "schtasks /run /tn VMTareas-Sysprep"
  shutdown_timeout = "45m"

  # extra_cd: CD opcional con el archivo de respuestas (lo usa Windows 11)
  # tools_iso: CD de VMware Tools que trae VMware Workstation (windows.iso); se instalan desde él
  vmx_data = {
    "firmware"           = "bios"
    "sata0.present"      = (var.extra_cd == "" && var.tools_iso == "") ? "FALSE" : "TRUE"
    "sata0:1.present"    = var.extra_cd == "" ? "FALSE" : "TRUE"
    "sata0:1.deviceType" = "cdrom-image"
    "sata0:1.fileName"   = var.extra_cd
    "sata0:3.present"    = var.tools_iso == "" ? "FALSE" : "TRUE"
    "sata0:3.deviceType" = "cdrom-image"
    "sata0:3.fileName"   = var.tools_iso
  }
  # Al terminar se desconectan los dos CD (los clones usan sata0:2 para su CD de configuración)
  vmx_data_post = {
    "sata0:1.present" = "FALSE"
    "sata0:3.present" = "FALSE"
  }
}

build {
  sources = ["source.vmware-iso.windows"]

  provisioner "powershell" {
    script = "${path.root}/windows/provision.ps1"
  }

  provisioner "windows-restart" {
    restart_timeout = "30m"
  }
}
