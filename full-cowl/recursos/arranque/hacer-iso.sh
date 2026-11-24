#!/bin/bash
# Rehace ubuntu-autoinstall.iso (mini-ISO de arranque, ficha 26). Se ejecuta en Linux (Ubuntu/Debian):
#   sudo apt-get install grub-pc-bin grub-efi-amd64-bin grub-common xorriso mtools
#   ./hacer-iso.sh
# La ISO lleva GRUB con arranque BIOS y EFI y el grub.cfg de esta carpeta. Nada mas.
set -euo pipefail
cd "$(dirname "$0")"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/boot/grub"
cp grub.cfg "$tmp/boot/grub/grub.cfg"
# Fecha fija para los archivos (aun asi la ISO no sale identica byte a byte cada vez: GRUB mete datos propios)
export SOURCE_DATE_EPOCH=1794441600
# Los de sistemas de archivos y de tablas de particiones van todos: si falta alguno, GRUB llena la pantalla de "file not found" al buscar el CD
fs="affs afs bfs btrfs cbfs cpio cpio_be exfat ext2 f2fs fat hfs hfsplus iso9660 jfs minix minix2 minix2_be minix3 minix3_be minix_be newc nilfs2 ntfs odc procfs reiserfs romfs sfs squash4 tar udf ufs1 ufs1_be ufs2 xfs zfs"
pm="part_acorn part_amiga part_apple part_bsd part_dfly part_dvh part_gpt part_msdos part_plan part_sun part_sunpc"
modulos="$fs $pm search search_fs_file test echo sleep linux halt nativedisk pata ahci ls normal configfile minicmd"
grub-mkrescue -o ubuntu-autoinstall.iso "$tmp" \
    --locales="" --fonts="" --themes="" \
    --install-modules="$modulos" \
    -- -volid FCARRANQUE -volume_date all_file_dates "=$SOURCE_DATE_EPOCH" 2>"$tmp/mkrescue.log" || { cat "$tmp/mkrescue.log"; exit 1; }
echo "Hecha: $(ls -la ubuntu-autoinstall.iso | awk '{print $5}') bytes"
echo "Arranques (tiene que salir uno BIOS y uno EFI):"
xorriso -indev ubuntu-autoinstall.iso -report_el_torito as_mkisofs 2>/dev/null | grep -E "^-b |^-e |^-c |no-emul-boot|eltorito|efi" || true
