#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from getopt import getopt, GetoptError
from sys import argv, exit

import plugins.loadconf
import plugins.servidores
import plugins.manager

def ayuda():
    print('''
        -t TAG          Etiqueta donde aplicar plugin   '?': lista de tags
        -p plugin       Plugin a usar                   '?': lista de plugins
        -o opciones     Opciones del plugin             '?': lista de opciones del plugin
''')

def leer_opciones(config):
    tag = config['DEFAULT']['tag']
    plugin = config['DEFAULT']['plugin']
    opciones_plugin = ''

    try:
        opts, args = getopt(argv[1:], 'ht:o:p:')
    except GetoptError as err:
        ayuda()
        exit(2)

    for opcion, argumento in opts:
        if opcion == '-h':
            ayuda()
            exit(0)
        elif opcion == '-t':
            tag = argumento
        elif opcion == '-p':
            plugin = argumento
        elif opcion == '-o':
            opciones_plugin = argumento
    opciones = {
                 'tag' : tag,
                 'plugin' : plugin,
                 'opts' : opciones_plugin,
                }

    return opciones

def main():
    config = plugins.loadconf.load_config()
    opciones = leer_opciones(config)
    servidores = plugins.servidores.init(config, opciones)
    result = plugins.manager.run(config, opciones, servidores)

    # result = gestion_opciones(opciones)

    # if not result:
    #     print('Errores en la ejecución del plugin: %s'%opciones[1])
    # else:
    #     print('Ejecución del plugin "%s" correcta.' %opciones[1])

if __name__ == '__main__':
    main()
