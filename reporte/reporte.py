#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from getopt import getopt, GetoptError
from sys import argv, exit

import plugins.loadconf
import plugins.servidores
import plugins.manager

def ayuda(err=0):
    print('''
        -t TAG          Etiqueta donde aplicar plugin   '?': lista de tags
        -p plugin       Plugin a usar                   '?': lista de plugins
        -o opciones     Opciones del plugin             '?': lista de opciones del plugin
''')
    exit(err)

def leer_opciones(config):
    tag = None
    plugin = None
    opciones_plugin = None
    try:
        opts, args = getopt(argv[1:], 'ht:o:p:')
    except GetoptError as err:
        ayuda(2)

    for opcion, argumento in opts:
        if opcion == '-h':
            ayuda()
        elif opcion == '-t':
            tag = argumento
        elif opcion == '-p':
            plugin = argumento
        elif opcion == '-o':
            opciones_plugin = argumento
    opciones = {
                 'tag' : tag,
                 'plugin' : plugin,
                 'plugin_opts' : opciones_plugin,
                }

    return opciones

def main():
    config = plugins.loadconf.load_config()
    opciones = leer_opciones(config)
    servidores = plugins.servidores.init(config, opciones)
    data = {
             'config' : config,
             'opts' : opciones,
             'servers' : servidores
            }
    result = plugins.manager.run(data)

    result = True
    if not result:
        print('Errores en la ejecución del plugin "%s".'%opciones['plugin'])
    else:
        print('Ejecución del plugin "%s" correcta.' %opciones['plugin'])

if __name__ == '__main__':
    main()
