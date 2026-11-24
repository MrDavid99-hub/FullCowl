#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Comprobación automática de Full Cowl (ficha 31).

Un solo programa, Python 3 y solo biblioteca estándar, que se ejecuta:
  - en el chat de código, antes de cada «git commit»:   python3 herramientas/comprobar.py
  - en GitHub, en cada subida (.github/workflows/comprobar.yml)
  - antes de publicar el repositorio (ficha 32)

Cada hallazgo sale como «ARCHIVO:LÍNEA mensaje». Dentro de GitHub, además, como
anotación (::error / ::warning) para que se vea marcado en el código.
Código de salida distinto de 0 si hay ERRORES. Los AVISOS no hacen fallar.

Las coincidencias ya revisadas y aceptadas se anotan en herramientas/comprobar-conocidos.txt
(una por línea: regla | archivo | clave | motivo). Solo las coincidencias nuevas hacen fallar.

Las cadenas privadas (nombres de equipo, correo...) se buscan con los patrones de
herramientas/privado.txt, que NO se sube. Nunca se imprime el valor encontrado.
"""
from __future__ import print_function

import argparse
import bisect
import fnmatch
import os
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

BOM = b'\xef\xbb\xbf'

# ----------------------------------------------------------------------------- tipos de archivo
BINARIOS = {'.png', '.ico', '.ttf', '.docx', '.zip', '.7z', '.ova', '.ovf', '.dll', '.exe', '.pdf',
            '.jpg', '.jpeg', '.gif', '.woff', '.woff2', '.bin', '.iso', '.vmdk', '.pyc'}
# Con LF fijado por .gitattributes (o por la ficha 31)
EXT_LF = {'.sh', '.hcl', '.plantilla', '.md', '.cs', '.xaml', '.json', '.py', '.fclab', '.yml', '.yaml'}
# De estos, .gitattributes no fija el final: en Windows con autocrlf pueden llegar enteros con CRLF
EXT_LF_LIBRES = {'.xaml', '.json', '.cs', '.yml', '.yaml'}
EXT_SIN_BOM = {'.sh', '.plantilla'}
EXT_UTF8 = {'.ps1', '.sh', '.hcl', '.plantilla', '.md', '.cs', '.xaml', '.json', '.py', '.fclab', '.yml',
            '.yaml', '.txt', '.xml'}

# Archivos y carpetas que no se suben nunca (ver .gitignore)
NUNCA_NOMBRES = {'config.local.json', 'password.sec', 'password.sec.antes', 'preferencias.json',
                 'segmentos.json', 'plantillas-laboratorio.json'}
NUNCA_EXTENSIONES = {'.log', '.lnk', '.sec'}
NUNCA_CARPETAS = {'estado', 'build', 'packer_cache'}

# Documentos internos (no se publican): ahí sí pueden salir las rutas de los PC de David y sus datos privados
DOCS_INTERNOS = {'CLAUDE.md', 'docs/PENDIENTE.md', 'docs/NOTAS-TECNICAS.md', 'docs/TRASPASO.md',
                 # revisiones y propuestas (docs/REVISION-*.md y docs/PROPUESTA-*.md): internas, no se publican (ficha 32)
                 'docs/REVISION-SEGURIDAD.md', 'docs/REVISION-CODIGO.md', 'docs/PROPUESTA-contrasena-dominio.md'}
# No se buscan cadenas privadas en estos (llevan los patrones o ejemplos de mentira)
SIN_BUSCAR_PRIVADO = {'herramientas/comprobar.py', 'herramientas/privado.ejemplo.txt',
                      'herramientas/privado.txt'}

CARPETA_INTERFAZ = 'full-cowl/interfaz/'
ARRANQUE_INTERFAZ = 'full-cowl/ventana-nueva.ps1'
# Variables automáticas de PowerShell: se escriben de varias formas y no son un problema
VARIABLES_PROPIAS = {
    'true', 'false', 'null', '_', 'args', 'input', 'this', 'psitem', 'pscmdlet', 'psscriptroot',
    'pscommandpath', 'pwd', 'home', 'host', 'error', 'matches', 'lastexitcode', 'erroractionpreference',
    'verbosepreference', 'progresspreference', 'confirmpreference', 'warningpreference',
    'debugpreference', 'informationpreference', 'psboundparameters', 'myinvocation', 'foreach', 'switch',
    'pid', 'profile', 'shellid', 'sender', 'eventargs', 'psversiontable', 'ofs', 'env', 'executioncontext',
    'stacktrace', 'psculture', 'psuiculture', 'psdefaultparametervalues', 'nestedpromptlevel',
}

DOS_PUNTOS = []     # (posición) de «$nombre:» dentro de cadenas (lo rellena limpiar_ps)
AMBITOS = ('env', 'script', 'global', 'local', 'private', 'using', 'variable', 'function', 'alias', 'env')
RE_VAR = re.compile(r'\$(?:\{[^}\r\n]*\}|(?:(?:script|global|local|private|using):)?\w+)')
RE_OCURRENCIA = re.compile(r'\$(?:(?P<p>script|global|local|private|using):)?(?P<n>\w+)\b(?!:\w)')
RE_ASIGNA = re.compile(r'(?<![\w$])\$(?:(?P<p>script|global|local|private):)?(?P<n>\w+)\s*[-+*/%]?=(?!=)')
RE_FOREACH = re.compile(r'(?i)\bforeach\s*\(\s*\$(?P<n>\w+)\s+in\b')
RE_FUNCION = re.compile(r'(?im)^[ \t]*(?:function|filter)\s+(?P<n>[\w:.-]+)')
RE_AQUI = re.compile(r'@([\'"])[ \t]*\r?\n')
XAML_NS = '{http://schemas.microsoft.com/winfx/2006/xaml}'


# ============================================================================= hallazgos
class Hallazgo(object):
    def __init__(self, nivel, regla, archivo, linea, mensaje, clave=''):
        self.nivel = nivel          # 'error' o 'aviso'
        self.regla = regla
        self.archivo = archivo
        self.linea = linea
        self.mensaje = mensaje
        self.clave = clave or ''
        self.aceptado = False


class Comprobador(object):
    def __init__(self, raiz, ruta_privado=None):
        self.raiz = raiz
        self.ruta_privado = ruta_privado or os.path.join(raiz, 'herramientas', 'privado.txt')
        self.hallazgos = []
        self.archivos = []          # todos los que se miran (relativos, con «/»)
        self.rastreados = None      # los que están en Git (None = no hay Git)
        self.xnames = {}            # archivo .xaml -> conjunto de x:Name que Elementos publica como variables
        self.usar_conocidos = True
        self.detalle = False
        self.conocidos = []         # [(regla, archivo, clave, motivo, línea, usado)]
        self.avisados = set()
        self.variables_asignadas = []   # para la regla 8 (se mira al final)
        self.patrones = []

    # ------------------------------------------------------------------------- utilidades
    def error(self, regla, archivo, linea, mensaje, clave=''):
        self.hallazgos.append(Hallazgo('error', regla, archivo, linea, mensaje, clave))

    def aviso(self, regla, archivo, linea, mensaje, clave=''):
        self.hallazgos.append(Hallazgo('aviso', regla, archivo, linea, mensaje, clave))

    def aviso_una_vez(self, regla, mensaje):
        if regla not in self.avisados:
            self.avisados.add(regla)
            self.aviso(regla, '(general)', None, mensaje)

    def ruta(self, rel):
        return os.path.join(self.raiz, *rel.split('/'))

    def leer(self, rel):
        with open(self.ruta(rel), 'rb') as f:
            return f.read()

    # ------------------------------------------------------------------------- qué archivos mirar
    def reunir_archivos(self):
        try:
            r1 = subprocess.run(['git', '-C', self.raiz, 'ls-files', '-z'], stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, check=True)
            r2 = subprocess.run(['git', '-C', self.raiz, 'ls-files', '-z', '-o', '--exclude-standard'],
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=True)
            rastreados = set(x for x in r1.stdout.decode('utf-8', 'replace').split('\0') if x)
            nuevos = set(x for x in r2.stdout.decode('utf-8', 'replace').split('\0') if x)
            self.rastreados = rastreados
            todos = rastreados | nuevos
        except (OSError, subprocess.CalledProcessError):
            self.rastreados = None
            todos = set()
            for base, carpetas, nombres in os.walk(self.raiz):
                carpetas[:] = [d for d in carpetas if d not in ('.git', '__pycache__', 'node_modules')]
                for n in nombres:
                    p = os.path.relpath(os.path.join(base, n), self.raiz).replace(os.sep, '/')
                    todos.add(p)
            self.aviso_una_vez('sin-git', 'No hay Git aquí: se miran todos los archivos de la carpeta y no se '
                                          'puede comprobar la lista de archivos que nunca se suben.')
        self.archivos = sorted(f for f in todos
                               if '__pycache__' not in f.split('/') and os.path.isfile(self.ruta(f)))

    # ------------------------------------------------------------------------- comprobaciones por archivo
    def comprobar_archivos(self):
        for rel in self.archivos:
            ext = os.path.splitext(rel)[1].lower()
            if ext in BINARIOS:
                continue
            try:
                datos = self.leer(rel)
            except OSError as e:
                self.aviso('lectura', rel, None, 'No he podido leer el archivo: %s' % e.__class__.__name__)
                continue
            texto = datos.decode('utf-8', 'replace')
            if texto.startswith('\ufeff'):
                texto = texto[1:]
            if ext in EXT_UTF8:
                try:
                    datos.decode('utf-8')
                except UnicodeDecodeError as e:
                    linea = datos.count(b'\n', 0, e.start) + 1
                    self.error('utf8', rel, linea, 'El archivo no es UTF-8 válido.')
            if ext == '.ps1':
                self.mirar_ps1(rel, datos, texto)
            elif ext == '.bat':
                self.mirar_bat(rel, datos, texto)
            elif ext == '.xaml':
                self.mirar_finales_lf(rel, datos, ext)
                self.mirar_xaml(rel, datos, texto)
            elif ext == '.cs':
                self.mirar_finales_lf(rel, datos, ext)
                self.mirar_cs(rel, texto)
            elif ext in EXT_LF:
                self.mirar_finales_lf(rel, datos, ext)
            if ext in EXT_SIN_BOM and datos.startswith(BOM):
                self.error('sin-bom', rel, 1, 'El archivo lleva BOM (marca de UTF-8) y no debe llevarla.')
            if ext == '.sh':
                self.mirar_bash(rel, datos)
            self.mirar_privado_generico(rel, ext, texto)
            self.mirar_privado_patrones(rel, texto)
            self.mirar_packer_tildes(rel, ext, texto)

    # ---- finales de línea
    @staticmethod
    def lineas_lf_sueltos(datos):
        return [datos.count(b'\n', 0, m.start()) + 1 for m in re.finditer(b'(?<!\r)\n', datos)]

    @staticmethod
    def lineas_crlf(datos):
        return [datos.count(b'\n', 0, m.start()) + 1 for m in re.finditer(b'\r\n', datos)]

    @staticmethod
    def resumen_lineas(lineas):
        if len(lineas) == 1:
            return 'línea %d' % lineas[0]
        return 'líneas %s%s (%d en total)' % (', '.join(str(x) for x in lineas[:3]),
                                              ', ...' if len(lineas) > 3 else '', len(lineas))

    def mirar_finales_lf(self, rel, datos, ext):
        crlf = self.lineas_crlf(datos)
        if not crlf:
            return
        lf = self.lineas_lf_sueltos(datos)
        if ext == '.cs':
            if lf:
                self.aviso('lf-finales', rel, crlf[0], 'Mezcla finales CRLF y LF (los .cs pueden venir con '
                                                       'CRLF desde Windows, pero no mezclados).')
            return
        if not lf and ext in EXT_LF_LIBRES and sys.platform.startswith('win'):
            return      # Windows con autocrlf: se arregla solo al subir
        self.error('lf-finales', rel, crlf[0],
                   'Debe tener finales de línea LF y tiene CRLF (%s).' % self.resumen_lineas(crlf))

    def mirar_ps1(self, rel, datos, texto):
        if rel == 'instalar.ps1':
            # Excepción (ficha 33): se ejecuta con «irm | iex», que en PowerShell 5.1 rompe con BOM y con tildes
            if datos.startswith(BOM):
                self.error('instalar-ascii', rel, 1, 'instalar.ps1 no debe llevar BOM (se ejecuta con «irm | iex»).')
            no_ascii = [datos.count(b'\n', 0, m.start()) + 1 for m in re.finditer(b'[\x80-\xff]', datos)]
            if no_ascii:
                self.error('instalar-ascii', rel, no_ascii[0], 'instalar.ps1 debe ser solo ASCII (sin tildes ni «»).')
            crlf = self.lineas_crlf(datos)
            if crlf:
                self.error('instalar-ascii', rel, crlf[0], 'instalar.ps1 debe tener finales LF.')
            return
        if not datos.startswith(BOM):
            self.error('ps1-bom', rel, 1, 'Falta el BOM de UTF-8 (sin él, PowerShell 5.1 rompe los acentos).')
        lf = self.lineas_lf_sueltos(datos)
        if lf:
            self.error('ps1-finales', rel, lf[0], 'Debe tener finales CRLF y hay LF sueltos (%s).'
                       % self.resumen_lineas(lf))
        del DOS_PUNTOS[:]
        limpio = limpiar_ps(texto)
        for pos in DOS_PUNTOS:
            nombre = re.match(r'\$\w+', texto[pos:]).group(0)
            self.error('ps1-dospuntos', rel, texto.count('\n', 0, pos) + 1,
                       'En una cadena, «%s:» se lee como variable con ámbito y da error. Escribir «${%s}:».'
                       % (nombre, nombre[1:]), clave=nombre)
        total = texto.count('\n') + 1
        if total > 3000:
            self.aviso('ps1-largo', rel, None, 'El archivo tiene %d líneas (más de 3000): conviene partirlo.' % total)
        for a, b, nombre in (('{', '}', 'llaves'), ('(', ')', 'paréntesis'), ('[', ']', 'corchetes')):
            if limpio.count(a) != limpio.count(b):
                self.aviso('equilibrio', rel, None, 'Posible desajuste de %s: %d de apertura y %d de cierre '
                           '(solo es una pista).' % (nombre, limpio.count(a), limpio.count(b)))
        self.mirar_variables(rel, limpio)

    # ---- .bat
    def mirar_bat(self, rel, datos, texto):
        lf = self.lineas_lf_sueltos(datos)
        if lf:
            self.error('bat-finales', rel, lf[0], 'Debe tener finales CRLF y hay LF sueltos (%s).'
                       % self.resumen_lineas(lf))
        for n, linea in enumerate(texto.split('\n'), 1):
            if re.match(r'(?i)^\s*@?echo(?:[\s.(:/\\]|$)', linea) and re.search(r'[^\x00-\x7f]', linea):
                self.error('bat-echo', rel, n, 'Hay acentos o caracteres no ASCII en un echo (se ven mal en la consola).')

    # ---- .sh
    def mirar_bash(self, rel, datos):
        if not shutil.which('bash'):
            self.aviso_una_vez('sin-bash', 'No encuentro bash: no se comprueba la sintaxis de los .sh.')
            return
        try:
            r = subprocess.run(['bash', '-n'], input=datos, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                               timeout=30)
        except (OSError, subprocess.TimeoutExpired):
            self.aviso('bash-sintaxis', rel, None, 'No he podido ejecutar bash -n.')
            return
        if r.returncode != 0:
            salida = r.stderr.decode('utf-8', 'replace')
            m = re.search(r'line (\d+)', salida)
            if m:
                self.error('bash-sintaxis', rel, int(m.group(1)), 'bash -n encuentra un error de sintaxis.')
            else:
                self.aviso('bash-sintaxis', rel, None, 'bash -n no ha podido leer el script.')

    # ---- .xaml
    def mirar_xaml(self, rel, datos, texto):
        hay_comentario = False
        for m in re.finditer(r'<!--(.*?)-->', texto, re.S):
            interior = m.group(1)
            if '--' in interior or interior.endswith('-'):
                hay_comentario = True
                pos = m.start() + 4 + (interior.find('--') if '--' in interior else 0)
                linea = texto.count('\n', 0, pos) + 1
                self.error('xaml-comentario', rel, linea, 'Un comentario XAML lleva «--» dentro (rompe la carga).')
        # Un {StaticResource X} solo ve los recursos escritos ANTES en el mismo archivo (si X está más abajo, la ventana
        # sale en blanco con «No se puede encontrar el recurso»; pasó con BotonRapido el 11/11/2026). Los comentarios se
        # tapan con espacios para no mover las posiciones.
        sin_coment = re.sub(r'<!--.*?-->', lambda m: re.sub(r'[^\n]', ' ', m.group(0)), texto, flags=re.S)
        definidos = {}
        for m in re.finditer(r'x:Key="([^"]+)"', sin_coment):
            definidos.setdefault(m.group(1), m.start())
        for m in re.finditer(r'\{StaticResource\s+([\w.]+)\s*\}', sin_coment):
            nombre = m.group(1)
            if nombre in definidos and definidos[nombre] > m.start():
                self.error('xaml-recurso-adelantado', rel, texto.count('\n', 0, m.start()) + 1,
                           'StaticResource «%s» se usa antes de definirse en este archivo: ponerlo antes (o usar DynamicResource).' % nombre,
                           nombre)
        try:
            raiz = ET.fromstring(datos)
            self.xnames[rel] = nombres_publicables(raiz)
        except ET.ParseError as e:
            if not hay_comentario:
                linea = e.position[0] if getattr(e, 'position', None) else None
                self.error('xaml-xml', rel, linea, 'El XAML no es XML bien formado: %s.' % str(e).split(':')[0])

    # ---- .cs (C# 5: el compilador de PowerShell 5.1)
    def mirar_cs(self, rel, texto):
        limpio, interpoladas = limpiar_cs(texto)
        for linea in interpoladas:
            self.error('csharp5', rel, linea, 'Cadena interpolada $"..." (no existe en C# 5).')
        for n, linea in enumerate(limpio.split('\n'), 1):
            if re.search(r'[\w)\]]\?\.[A-Za-z_\[]', linea):
                self.error('csharp5', rel, n, 'Operador ?. (no existe en C# 5).')
            if re.search(r'\bnameof\s*\(', linea):
                self.error('csharp5', rel, n, 'nameof (no existe en C# 5).')
            if re.search(r'\b(?:get|set)\s*=>', linea):
                self.error('csharp5', rel, n, 'Propiedad con cuerpo de expresión (=>) no existe en C# 5.')
            elif '=>' in linea:
                antes = linea.split('=>')[0]
                if '{' in antes or ';' in antes:
                    continue    # hay un cuerpo con llaves: el => es una lambda de dentro
                if re.match(r'^\s*(?:(?:public|private|protected|internal|static|override|virtual|sealed|abstract|'
                            r'new|readonly|partial|extern|unsafe)\s+)+', antes) and \
                        not re.search(r'(?<![=!<>])=(?!=)', antes):
                    self.error('csharp5', rel, n, 'Miembro con cuerpo de expresión (=>) no existe en C# 5.')
                elif re.match(r'^\s*[\w<>\[\],.? ]+\([^()]*\)\s*$', antes):
                    self.aviso('csharp5-posible', rel, n, 'Posible miembro con cuerpo de expresión (=>): '
                                                         'en C# 5 hay que usar llaves y return.')

    # ---- variables de PowerShell
    def mirar_variables(self, rel, limpio):
        inicios = [0] + [m.end() for m in re.finditer(r'\n', limpio)]

        def linea_de(pos):
            return bisect.bisect_right(inicios, pos)

        # Funciones: (inicio, fin, nombre)
        tramos = []
        for m in RE_FUNCION.finditer(limpio):
            a = limpio.find('{', m.end())
            if a < 0:
                continue
            prof, i = 0, a
            while i < len(limpio):
                c = limpio[i]
                if c == '{':
                    prof += 1
                elif c == '}':
                    prof -= 1
                    if prof == 0:
                        break
                i += 1
            tramos.append((a, i, m.group('n')))

        def ambito(pos):
            mejor = None
            for a, b, nombre in tramos:
                if a <= pos <= b and (mejor is None or a > mejor[0]):
                    mejor = (a, b, nombre)
            return mejor[2] if mejor else '<script>'

        # 7. Grafías distintas del mismo nombre en la misma función o script
        por_ambito = {}
        for m in RE_OCURRENCIA.finditer(limpio):
            nombre = m.group('n')
            if nombre.isdigit() or nombre.lower() in VARIABLES_PROPIAS:
                continue
            d = por_ambito.setdefault(ambito(m.start()), {}).setdefault(nombre.lower(), {})
            d.setdefault(nombre, []).append(m.start())
        for amb, nombres in por_ambito.items():
            for bajo, grafias in nombres.items():
                if len(grafias) > 1:
                    # se marca la grafía menos usada (si empatan, la que aparece después)
                    menos = sorted(grafias.items(), key=lambda kv: (len(kv[1]), -kv[1][0]))[0]
                    lista = ', '.join('$' + g for g in sorted(grafias))
                    donde = 'la función «%s»' % amb if amb != '<script>' else 'el código principal'
                    self.error('variables-mayusculas', rel, linea_de(menos[1][0]),
                               'La variable «$%s» está escrita de varias formas en %s (%s): PowerShell las '
                               'trata como la misma.' % (bajo, donde, lista), '%s:%s' % (amb, bajo))
        # 8. Asignaciones que pisan un x:Name publicado (solo código de la interfaz nueva)
        if rel.startswith(CARPETA_INTERFAZ) or rel == ARRANQUE_INTERFAZ:
            self.variables_asignadas.append((rel, limpio, linea_de, ambito))

    def mirar_pisadas(self):
        """Regla 8. Se hace al final, cuando ya se han leído todos los .xaml."""
        publicados = {}
        for rel, nombres in self.xnames.items():
            if not rel.startswith(CARPETA_INTERFAZ):
                continue
            base = rel[len(CARPETA_INTERFAZ):]
            if base.startswith(('dialogo-', 'asistente', 'estilos', 'iconos', 'logos')):
                continue    # no se publican como variables del script (usan una tabla local)
            for n in nombres:
                publicados.setdefault(n.lower(), set()).add(n)
        for rel, limpio, linea_de, ambito in self.variables_asignadas:
            vistos = set()
            candidatos = [(m.start(), m.group('n'), m.group('p')) for m in RE_ASIGNA.finditer(limpio)]
            candidatos += [(m.start('n'), m.group('n'), None) for m in RE_FOREACH.finditer(limpio)]
            for pos, nombre, prefijo in candidatos:
                bajo = nombre.lower()
                if bajo not in publicados or (nombre, ambito(pos)) in vistos:
                    continue
                if prefijo == 'script' and nombre in publicados[bajo]:
                    continue    # se actualiza a propósito la variable publicada
                vistos.add((nombre, ambito(pos)))
                self.error('variable-pisa-xname', rel, linea_de(pos),
                           'Se asigna «$%s», que coincide con el x:Name «%s» de la interfaz: tapa al elemento '
                           'publicado (usa otro nombre).' % (nombre, sorted(publicados[bajo])[0]),
                           '%s:%s' % (ambito(pos), bajo))

    # ------------------------------------------------------------------------- cadenas privadas
    def cargar_patrones_privados(self):
        self.patrones = []
        if not os.path.isfile(self.ruta_privado):
            self.aviso_una_vez('privado-patrones',
                               'No hay herramientas/privado.txt: se salta la búsqueda de cadenas privadas '
                               '(copia privado.ejemplo.txt a privado.txt y pon tus patrones).')
            return
        with open(self.ruta_privado, 'rb') as f:
            lineas = f.read().decode('utf-8', 'replace').lstrip('\ufeff').splitlines()
        for n, linea in enumerate(lineas, 1):
            linea = linea.strip()
            if not linea or linea.startswith('#'):
                continue
            try:
                self.patrones.append((len(self.patrones) + 1, re.compile(linea, re.I)))
            except re.error:
                self.error('privado-patrones', 'herramientas/privado.txt', n,
                           'El patrón de esta línea no es una expresión regular válida.')
        if not self.patrones:
            self.aviso_una_vez('privado-patrones', 'herramientas/privado.txt no tiene ningún patrón.')

    def mirar_privado_patrones(self, rel, texto):
        if rel in SIN_BUSCAR_PRIVADO or rel in DOCS_INTERNOS or not getattr(self, 'patrones', None):
            return      # los documentos internos no se publican: ahí pueden ir los nombres de equipo, etc.
        for n, linea in enumerate(texto.split('\n'), 1):
            for num, patron in self.patrones:
                if patron.search(linea):
                    self.error('privado', rel, n, 'Coincide con el patrón privado nº %d (el valor no se muestra).' % num)

    GENERICOS = [
        ('contrasena-fija', re.compile(r"""-Password\s+(?:'[^'$\r\n]+'|"[^"$\r\n]+")""", re.I),
         'Contraseña escrita a mano con -Password.', None),
        ('contrasena-fija', re.compile(r"""\bpassword\w*\s*[:=]\s*['"][^'"$%{|()\r\n]{3,}['"]""", re.I),
         'Contraseña escrita a mano («password = "..."»).', None),
        ('contrasena-fija', re.compile(r"""\bpassword\w*\s*=\s*(?![$%{\[(<@'"\s])[^\s'",;)]{3,}""", re.I),
         'Contraseña escrita a mano («password=valor»).', {'.sh', '.cfg', '.md', '.hcl', '.plantilla', '.bat',
                                                          '.txt', '.json', '.yml'}),
        ('clave-larga', re.compile(r'(?<![\w/+=.-])(?=[A-Za-z0-9+/_=-]*[A-Z])(?=[A-Za-z0-9+/_=-]*[a-z])'
                                   r'(?=[A-Za-z0-9+/_=-]*\d)[A-Za-z0-9+/_=-]{40,}(?![\w+/=-])'),
         'Cadena larga con aspecto de clave o token.', None),
        ('correo', re.compile(r'[\w.+-]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)+'),
         'Dirección de correo.', None),
        ('ruta-usuario', re.compile(r'[A-Za-z]:\\Users\\(?!Public\b|Default\b|All Users\b|%|\$|<|\{|\*)'
                                    r'[^\\\s"\'<>|*?]+\\', re.I),
         'Ruta de una carpeta de usuario de Windows.', None),
        ('ruta-d', re.compile(r'\bD:\\[^\s"\'<>|*?]*', re.I),
         'Ruta D:\\ de un PC personal.', None),
    ]

    def mirar_privado_generico(self, rel, ext, texto):
        if rel in SIN_BUSCAR_PRIVADO:
            return
        interno = rel in DOCS_INTERNOS
        for n, linea in enumerate(texto.split('\n'), 1):
            for clave, patron, mensaje, solo_ext in self.GENERICOS:
                if solo_ext is not None and ext not in solo_ext:
                    continue
                if clave == 'ruta-d' and interno:
                    continue
                for m in patron.finditer(linea):
                    if clave == 'correo' and m.group(0).lower() == 'noreply@anthropic.com':
                        continue
                    if clave == 'correo' and m.group(0).lower().startswith('git@'):
                        continue
                    self.error('privado-generico', rel, n, mensaje + ' (el valor no se muestra).', clave)
                    break

    # ------------------------------------------------------------------------- Packer
    def mirar_packer_tildes(self, rel, ext, texto):
        if not rel.startswith('full-cowl/packer/') or ext not in {'.hcl', '.ps1', '.sh', '.plantilla', '.cfg'}:
            return
        for n, linea in enumerate(texto.split('\n'), 1):
            if re.search(r'(?i)\b(echo|Write-Host|Write-Output|Write-Warning|Write-Error)\b', linea) and \
                    re.search(r'[^\x00-\x7f]', linea):
                self.aviso('packer-tildes', rel, n, 'Mensaje de consola con tildes: en la consola de Packer se '
                                                    'ven mal (escribirlo sin tildes).')

    def mirar_packer_fmt(self):
        exe = shutil.which('packer')
        if not exe:
            return
        carpetas = sorted(set(os.path.dirname(f) for f in self.archivos if f.endswith('.pkr.hcl')))
        for c in carpetas:
            try:
                r = subprocess.run([exe, 'fmt', '-check', self.ruta(c) if c else self.raiz],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60)
            except (OSError, subprocess.TimeoutExpired):
                continue
            if r.returncode != 0:
                self.aviso('packer-fmt', c or '.', None, 'packer fmt -check dice que hay archivos sin formato.')

    # ------------------------------------------------------------------------- comprobaciones de conjunto
    def comprobar_nunca_subir(self):
        if self.rastreados is None:
            return
        for rel in sorted(self.rastreados):
            partes = rel.split('/')
            nombre = partes[-1]
            ext = os.path.splitext(nombre)[1].lower()
            if nombre in NUNCA_NOMBRES or ext in NUNCA_EXTENSIONES or any(p in NUNCA_CARPETAS for p in partes[:-1]):
                self.error('prohibido-en-git', rel, None, 'Este archivo no se sube nunca y está en Git '
                           '(quitarlo con «git rm --cached»).')

    def comprobar_version(self):
        try:
            version = self.leer('VERSION').decode('utf-8', 'replace').strip().lstrip('\ufeff')
            manual = self.leer('docs/MANUAL.md').decode('utf-8', 'replace')
        except OSError:
            self.aviso('version', 'VERSION', None, 'No encuentro VERSION o docs/MANUAL.md para comparar.')
            return
        m = re.search(r'Versi[oó]n del manual:\s*\**\s*([0-9][0-9.]*)', manual)
        if not m:
            self.error('version', 'docs/MANUAL.md', None, 'No encuentro la línea «Versión del manual».')
        elif m.group(1) != version:
            self.error('version', 'docs/MANUAL.md', manual.count('\n', 0, m.start()) + 1,
                       'La versión del manual (%s) no coincide con VERSION (%s).' % (m.group(1), version))

    # ------------------------------------------------------------------------- «conocidos»
    def cargar_conocidos(self):
        if not self.usar_conocidos:
            return
        ruta = self.ruta('herramientas/comprobar-conocidos.txt')
        if not os.path.isfile(ruta):
            return
        with open(ruta, 'rb') as f:
            lineas = f.read().decode('utf-8', 'replace').lstrip('\ufeff').splitlines()
        for n, linea in enumerate(lineas, 1):
            if not linea.strip() or linea.strip().startswith('#'):
                continue
            partes = [p.strip() for p in linea.split('|')]
            if len(partes) < 4 or not partes[3]:
                self.error('conocidos', 'herramientas/comprobar-conocidos.txt', n,
                           'Línea mal formada: debe ser «regla | archivo | clave | motivo» y el motivo es obligatorio.')
                continue
            self.conocidos.append([partes[0], partes[1], partes[2], partes[3], n, False])

    def aplicar_conocidos(self):
        for h in self.hallazgos:
            if h.regla in ('privado', 'privado-patrones', 'conocidos', 'prohibido-en-git'):
                continue    # esto nunca se acepta
            for c in self.conocidos:
                if c[0] == h.regla and fnmatch.fnmatchcase(h.archivo, c[1]) and \
                        fnmatch.fnmatchcase(h.clave, c[2]):
                    h.aceptado = True
                    c[5] = True
                    break
        for c in self.conocidos:
            if not c[5]:
                self.aviso('conocidos-sobra', 'herramientas/comprobar-conocidos.txt', c[4],
                           'Esta entrada ya no coincide con nada (se puede borrar).')

    # ------------------------------------------------------------------------- salida
    def informar(self):
        en_github = os.environ.get('GITHUB_ACTIONS') == 'true'
        nuevos = [h for h in self.hallazgos if not h.aceptado]
        errores = [h for h in nuevos if h.nivel == 'error']
        avisos = [h for h in nuevos if h.nivel == 'aviso']
        aceptados = [h for h in self.hallazgos if h.aceptado]

        def orden(h):
            return (h.archivo, h.linea or 0, h.regla)

        def texto(h):
            sitio = h.archivo if h.linea is None else '%s:%d' % (h.archivo, h.linea)
            extra = ' {%s}' % h.clave if (self.detalle and h.clave) else ''
            return '%s  %s  [%s%s]' % (sitio, h.mensaje, h.regla, extra)

        def anotar(h):
            def esc(s, prop=False):
                s = s.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')
                return s.replace(':', '%3A').replace(',', '%2C') if prop else s
            partes = [] if h.archivo == '(general)' else ['file=' + esc(h.archivo, True)]
            if h.linea:
                partes.append('line=%d' % h.linea)
            partes.append('title=' + esc(h.regla, True))
            print('::%s %s::%s' % ('error' if h.nivel == 'error' else 'warning', ','.join(partes), esc(h.mensaje)))

        if errores:
            print('ERRORES (%d):' % len(errores))
            for h in sorted(errores, key=orden):
                print('  ' + texto(h))
        if avisos:
            print('AVISOS (%d):' % len(avisos))
            for h in sorted(avisos, key=orden):
                print('  ' + texto(h))
        if en_github:
            for h in sorted(errores, key=orden) + sorted(avisos, key=orden):
                anotar(h)
        print('')
        resumen = '%d archivos revisados · %d errores · %d avisos' % (len(self.archivos), len(errores), len(avisos))
        if aceptados:
            resumen += ' · %d coincidencias ya aceptadas (herramientas/comprobar-conocidos.txt)' % len(aceptados)
        print(resumen)
        if errores:
            print('NO hay que hacer «git commit» hasta arreglar los errores. Si uno es un falso positivo, '
                  'se anota en herramientas/comprobar-conocidos.txt con su motivo.')
        else:
            print('Todo en orden: cero errores.')
        return 1 if errores else 0


def nombres_publicables(raiz):
    """x:Name que la interfaz publica como variables ($Lista...): los de dentro de plantillas y estilos no
    se encuentran con FindName, así que no cuentan."""
    nombres = set()

    def recorrer(el):
        etiqueta = el.tag.rsplit('}', 1)[-1] if isinstance(el.tag, str) else ''
        if etiqueta.endswith('Template') or etiqueta == 'Style':
            return
        n = el.get(XAML_NS + 'Name')
        if n:
            nombres.add(n)
        for hijo in el:
            recorrer(hijo)

    recorrer(raiz)
    return nombres


# ============================================================================= lectura de PowerShell
def limpiar_ps(src):
    """Devuelve el código con las MISMAS líneas y posiciones, pero con comentarios y cadenas en blanco.
    En las cadenas con comillas dobles se dejan las variables ($nombre) y las subexpresiones $( ),
    porque son código de verdad."""
    n = len(src)
    out = list(src)

    def blanquear(a, b):
        for k in range(a, min(b, n)):
            if out[k] not in '\r\n':
                out[k] = ' '

    def paso_expandible(j):
        c = src[j]
        if c == '`':
            blanquear(j, j + 2)
            return j + 2
        if c == '$':
            if src.startswith('$(', j):
                blanquear(j, j + 2)
                return codigo(j + 2, True)
            m = RE_VAR.match(src, j)
            if m:
                fin = m.end()
                if (src.startswith(':', fin) and not src.startswith('::', fin)
                        and not m.group(0).startswith('${')):
                    nombre = m.group(0)[1:]
                    sigue = src[fin + 1:fin + 2]
                    if not (nombre.lower() in AMBITOS and (sigue.isalnum() or sigue in '_{')):
                        DOS_PUNTOS.append(j)
                return fin
        blanquear(j, j + 1)
        return j + 1

    def cadena_doble(i):
        blanquear(i, i + 1)
        j = i + 1
        while j < n:
            c = src[j]
            if c == '"':
                if j + 1 < n and src[j + 1] == '"':
                    blanquear(j, j + 2)
                    j += 2
                    continue
                blanquear(j, j + 1)
                return j + 1
            j = paso_expandible(j)
        return j

    def codigo(i, subexpresion):
        prof = 0
        while i < n:
            c = src[i]
            if c == '<' and src.startswith('<#', i):
                j = src.find('#>', i + 2)
                j = n if j < 0 else j + 2
                blanquear(i, j)
                i = j
                continue
            if c == '#' and (i == 0 or src[i - 1] in ' \t\r\n;({[,|&=})'):
                j = src.find('\n', i)
                j = n if j < 0 else j
                blanquear(i, j)
                i = j
                continue
            if c == '@' and i + 1 < n and src[i + 1] in '\'"':
                m = RE_AQUI.match(src, i)
                if m:
                    q = src[i + 1]
                    fin = src.find('\n' + q + '@', m.end() - 1)
                    if fin < 0:
                        fin = n
                    if q == "'":
                        blanquear(i, fin + 3)
                    else:
                        blanquear(i, m.end())
                        j = m.end()
                        while j < fin:
                            j = paso_expandible(j)
                        blanquear(fin, fin + 3)
                    i = min(n, fin + 3)
                    continue
            if c == "'":
                j = i + 1
                while j < n:
                    if src[j] == "'":
                        if j + 1 < n and src[j + 1] == "'":
                            j += 2
                            continue
                        break
                    j += 1
                blanquear(i, j + 1)
                i = j + 1
                continue
            if c == '"':
                i = cadena_doble(i)
                continue
            if c == '`':
                blanquear(i, i + 2)
                i += 2
                continue
            if subexpresion:
                if c == '(':
                    prof += 1
                elif c == ')':
                    if prof == 0:
                        blanquear(i, i + 1)
                        return i + 1
                    prof -= 1
            i += 1
        return i

    codigo(0, False)
    return ''.join(out)


def limpiar_cs(src):
    """Quita comentarios y cadenas de un .cs (mismas líneas). Devuelve (código, líneas con $"...")."""
    n = len(src)
    out = list(src)
    interpoladas = []
    i = 0

    def blanquear(a, b):
        for k in range(a, min(b, n)):
            if out[k] not in '\r\n':
                out[k] = ' '

    while i < n:
        c = src[i]
        if c == '/' and src.startswith('//', i):
            j = src.find('\n', i)
            j = n if j < 0 else j
            blanquear(i, j)
            i = j
        elif c == '/' and src.startswith('/*', i):
            j = src.find('*/', i + 2)
            j = n if j < 0 else j + 2
            blanquear(i, j)
            i = j
        elif c in '$@' and re.match(r'(\$@|@\$|\$|@)"', src[i:i + 3]):
            m = re.match(r'(\$@|@\$|\$|@)"', src[i:i + 3])
            prefijo = m.group(1)
            if '$' in prefijo:
                interpoladas.append(src.count('\n', 0, i) + 1)
            j = i + len(prefijo) + 1
            if '@' in prefijo:
                while j < n:
                    if src[j] == '"':
                        if j + 1 < n and src[j + 1] == '"':
                            j += 2
                            continue
                        break
                    j += 1
            else:
                while j < n and src[j] != '"':
                    j += 2 if src[j] == '\\' else 1
            blanquear(i, j + 1)
            i = j + 1
        elif c == '"':
            j = i + 1
            while j < n and src[j] != '"':
                j += 2 if src[j] == '\\' else 1
            blanquear(i, j + 1)
            i = j + 1
        elif c == "'":
            j = i + 1
            while j < n and src[j] != "'":
                j += 2 if src[j] == '\\' else 1
            blanquear(i, j + 1)
            i = j + 1
        else:
            i += 1
    return ''.join(out), interpoladas


# ============================================================================= programa
def main(argv=None):
    for flujo in (sys.stdout, sys.stderr):
        try:
            flujo.reconfigure(encoding='utf-8', errors='replace')
        except (AttributeError, ValueError):
            pass
    ap = argparse.ArgumentParser(description='Comprobación automática de Full Cowl (ficha 31).')
    ap.add_argument('--raiz', default=None, help='Carpeta del repositorio (por defecto, la de este programa).')
    ap.add_argument('--sin-conocidos', action='store_true',
                    help='Ignora comprobar-conocidos.txt para ver TODAS las coincidencias (pasada antes de publicar).')
    ap.add_argument('--detalle', action='store_true',
                    help='Muestra también la «clave» de cada coincidencia (para escribir comprobar-conocidos.txt).')
    ap.add_argument('--privado', default=None, help='Archivo con los patrones privados (por defecto '
                                                    'herramientas/privado.txt).')
    args = ap.parse_args(argv)
    raiz = os.path.abspath(args.raiz) if args.raiz else \
        os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

    c = Comprobador(raiz, args.privado)
    c.usar_conocidos = not args.sin_conocidos
    c.detalle = args.detalle
    c.reunir_archivos()
    c.cargar_conocidos()
    c.cargar_patrones_privados()
    c.comprobar_archivos()
    c.mirar_pisadas()
    c.comprobar_nunca_subir()
    c.comprobar_version()
    c.mirar_packer_fmt()
    c.aplicar_conocidos()
    return c.informar()


if __name__ == '__main__':
    sys.exit(main())
