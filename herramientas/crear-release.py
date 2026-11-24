#!/usr/bin/env python3
"""Construye lo que se adjunta a cada Release de Full Cowl (ficha 33).

    python herramientas/crear-release.py [--salida dist]

Deja en la carpeta de salida:
  Full-Cowl.zip     el programa (sin herramientas/, .github/ ni docs/img/), con los archivos en la raíz del ZIP
  MANIFIESTO.txt    «<sha256>  <ruta>» de cada archivo del ZIP (lo usa la actualización sin Git)
  SHA256SUMS.txt    sumas de Full-Cowl.zip y MANIFIESTO.txt (lo comprueban instalar.ps1 y actualizar.ps1)
  notas.md          el texto de la versión, sacado del CHANGELOG (para la página de la Release)

Se ejecuta normalmente en el repositorio público (GitHub Actions, al subir una etiqueta v*). También funciona en
la copia de trabajo para probar: si existe herramientas/publicacion.json (que no se publica), aplica además sus
exclusiones, quita los bloques marcados «solo-privado» y pone la dirección del repositorio público.
"""
import argparse
import hashlib
import json
import os
import re
import subprocess
import sys
import zipfile

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
EXCLUIR_DEL_ZIP = ['herramientas/', '.github/', 'docs/img/', '.gitattributes', '.gitignore']
FECHA_ZIP = (2026, 1, 1, 0, 0, 0)      # fecha fija: el mismo contenido da el mismo ZIP
EXT_TEXTO = {'.ps1', '.bat', '.md', '.txt', '.json', '.xaml', '.cs', '.sh', '.hcl', '.plantilla', '.xml', '.cfg',
             '.py', '.yml', '.fclab', ''}

# Marcas de lo que es solo de la copia de trabajo (ficha 32). Siempre rodean líneas enteras.
# (Se escriben por partes para que este archivo no se recorte a sí mismo al publicarse.)
_M = 'solo' + '-privado'
MARCA_INICIO = re.compile(r'<!--\s*' + _M + r'\s*-->|<' + _M + '>')
MARCA_FIN = re.compile(r'<!--\s*/' + _M + r'\s*-->|</' + _M + '>')


def quitar_marcas(texto, nombre=''):
    """Quita los bloques solo-privado (de la línea de inicio a la de fin, ambas incluidas)."""
    lineas = texto.splitlines(keepends=True)
    fuera, dentro, inicio = [], False, 0
    for n, linea in enumerate(lineas, 1):
        if not dentro and MARCA_INICIO.search(linea):
            if MARCA_FIN.search(linea[MARCA_INICIO.search(linea).end():]):
                continue                          # bloque de una sola línea
            dentro, inicio = True, n
            continue
        if dentro:
            if MARCA_FIN.search(linea):
                dentro = False
            continue
        if MARCA_FIN.search(linea):
            raise ValueError('%s:%d: marca de fin «solo-privado» sin su inicio' % (nombre, n))
        fuera.append(linea)
    if dentro:
        raise ValueError('%s:%d: marca «solo-privado» sin cerrar' % (nombre, inicio))
    return ''.join(fuera)


def leer_publicacion():
    ruta = os.path.join(RAIZ, 'herramientas', 'publicacion.json')
    if not os.path.isfile(ruta):
        return None
    with open(ruta, encoding='utf-8') as f:
        return json.load(f)


def archivos_del_repositorio():
    r = subprocess.run(['git', '-C', RAIZ, 'ls-files', '-z'], stdout=subprocess.PIPE, check=True)
    return sorted(p for p in r.stdout.decode('utf-8').split('\0') if p and os.path.isfile(os.path.join(RAIZ, p)))


def excluido(ruta, lista):
    return any(ruta == e or (e.endswith('/') and ruta.startswith(e)) for e in lista)


def contenido_publico(ruta, pub):
    """Bytes del archivo tal como se publica (sin marcas y con la dirección pública)."""
    with open(os.path.join(RAIZ, ruta), 'rb') as f:
        datos = f.read()
    if os.path.splitext(ruta)[1].lower() not in EXT_TEXTO:
        return datos
    try:
        texto = datos.decode('utf-8')
    except UnicodeDecodeError:
        return datos
    texto = quitar_marcas(texto, ruta)
    if pub:
        texto = poner_repo(texto, pub['repoPublico'])
    return texto.encode('utf-8')


def poner_repo(texto, repo):
    texto = texto.replace('MrDavid99-hub/FullCowl', repo)
    # Url-RepoPublico (comun.ps1): la dirección pública para «Acerca de» (en la copia de trabajo está vacía)
    return texto.replace("    $u = ''\r\n    if ($u -match '^https://github", "    $u = 'https://github.com/%s'\r\n    if ($u -match '^https://github" % repo)


def notas_de_version(version, archivo_changelog):
    """Texto de «## <versión> …» hasta el siguiente «## » del CHANGELOG."""
    if not os.path.isfile(archivo_changelog):
        return 'Full Cowl %s' % version
    with open(archivo_changelog, encoding='utf-8-sig') as f:
        lineas = f.read().splitlines()
    fuera, dentro = [], False
    for linea in lineas:
        if linea.startswith('## '):
            if dentro:
                break
            dentro = linea[3:].strip().startswith(version)
            continue
        if dentro:
            fuera.append(linea)
    return '\n'.join(fuera).strip() or 'Full Cowl %s' % version


def sha256(datos):
    return hashlib.sha256(datos).hexdigest()


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--salida', default=os.path.join(RAIZ, 'dist'))
    args = ap.parse_args()

    pub = leer_publicacion()
    excluir = list(EXCLUIR_DEL_ZIP)
    if pub:
        excluir += pub.get('excluir', []) + pub.get('excluirDelZip', [])
    with open(os.path.join(RAIZ, 'VERSION'), encoding='utf-8-sig') as f:
        version = f.read().strip()

    os.makedirs(args.salida, exist_ok=True)
    archivos = [a for a in archivos_del_repositorio() if not excluido(a, excluir)]
    # En la copia de trabajo, los archivos de publico/ sustituyen a los de la raíz (README, CHANGELOG...)
    sustitutos = {}
    if pub and os.path.isdir(os.path.join(RAIZ, 'publico')):
        for base, _, nombres in os.walk(os.path.join(RAIZ, 'publico')):
            for n in nombres:
                origen = os.path.relpath(os.path.join(base, n), RAIZ).replace(os.sep, '/')
                destino = origen[len('publico/'):]
                if not excluido(destino, EXCLUIR_DEL_ZIP + pub.get('excluirDelZip', [])):
                    sustitutos[destino] = origen
    nombres = sorted(set(archivos) | set(sustitutos))

    manifiesto, contenidos = [], {}
    for nombre in nombres:
        datos = contenido_publico(sustitutos.get(nombre, nombre), pub)
        contenidos[nombre] = datos
        manifiesto.append('%s  %s' % (sha256(datos), nombre))
    texto_manifiesto = ('\r\n'.join(manifiesto) + '\r\n').encode('utf-8')

    ruta_zip = os.path.join(args.salida, 'Full-Cowl.zip')
    with zipfile.ZipFile(ruta_zip, 'w', zipfile.ZIP_DEFLATED, compresslevel=9) as z:
        for nombre in nombres + ['MANIFIESTO.txt']:
            info = zipfile.ZipInfo(nombre, FECHA_ZIP)
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, contenidos.get(nombre, texto_manifiesto))
    with open(os.path.join(args.salida, 'MANIFIESTO.txt'), 'wb') as f:
        f.write(texto_manifiesto)
    with open(ruta_zip, 'rb') as f:
        suma_zip = sha256(f.read())
    with open(os.path.join(args.salida, 'SHA256SUMS.txt'), 'w', encoding='ascii', newline='\r\n') as f:
        f.write('%s  Full-Cowl.zip\n%s  MANIFIESTO.txt\n' % (suma_zip, sha256(texto_manifiesto)))
    changelog = os.path.join(RAIZ, sustitutos.get('CHANGELOG.md', 'CHANGELOG.md'))
    with open(os.path.join(args.salida, 'notas.md'), 'w', encoding='utf-8') as f:
        f.write(notas_de_version(version, changelog) + '\n')
    print('Full Cowl %s: %d archivos en Full-Cowl.zip (%s)' % (version, len(nombres), args.salida))
    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except (ValueError, subprocess.CalledProcessError, OSError) as e:
        print('ERROR: %s' % e, file=sys.stderr)
        sys.exit(1)
