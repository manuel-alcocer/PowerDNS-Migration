#!/usr/bin/env python3
# -*- coding: utf-8 -*-

from yaml import dump as dyml, load as lyml
from getopt import getopt, GetoptError
from sys import argv, exit

import plugins.database
import plugins.discos

FICHERO = '/home/manuel/gitlab/ansible_playbooks/utils/hosts_inventory.yml'
CONTRASENYAS = '/home/manuel/gitlab/ansible_playbooks/utils/group_vars/all'

DEFAULTTAG = 'alcocer'
DEFAULTPLUGIN = 'espacio_discos'

# DATOS DE CONEXIÓN
BBDD = {
        'db' : 'reporte',
        'user' : 'reporte',
        'pass' : 'reporte',
        'host' : 'localhost'
        }

def ayuda():
    print('''
        -t TAG          Etiqueta (default: %s)
        -p plugin       Plugin a usar (defecto: %s)
                        Lista: espacio_discos,poblar_servidores, check_db
        -o opciones     Opciones del plugin
''' %(DEFAULTTAG, DEFAULTPLUGIN))

def unir_listas(servidores, passwords, etiqueta):
    lista = []
    servidores = servidores['all']['children'][etiqueta]['hosts']
    for key in servidores.keys():
        hostdict = {
                    'alias' : key,
                    'host' : servidores[key]['ansible_host'],
                    'port' : servidores[key]['ansible_port'],
                    'user' : servidores[key]['ansible_user'],
                    'pass' : passwords['%s_PASSWD' %(key.replace('-','_'),)],
                }
        lista.append(hostdict)
    return lista

def obtener_lista(fichero, contrasenyas,etiqueta):
    with open(fichero, 'r') as f:
        diccionario_servers = lyml(f)

    with open(contrasenyas, 'r') as f:
        diccionario_pass = lyml(f)
    lista = unir_listas(diccionario_servers, diccionario_pass, etiqueta)

    return lista

def leer_parametros():
    database = BBDD
    try:
        opts, args = getopt(argv[1:], 'ho:t:p:')
    except GetoptError as err:
        ayuda()
        exit(2)

    etiqueta = DEFAULTTAG
    plugin = DEFAULTPLUGIN
    for opcion, argumento in opts:
        if opcion == '-h':
            ayuda()
            exit(0)
        elif opcion == '-t':
            etiqueta = argumento
        elif opcion == '-p':
            plugin = argumento
        elif opcion == '-o':
            opciones_plugin = argumento

    return [etiqueta, plugin]

def aplica_plugin(plugin, db, servidores):
    if plugin == 'espacio_discos':
        result = plugins.discos.espacio_discos(db, servidores)
    elif plugin == 'poblar_servidores':
        result = plugins.poblar_servidores(db, servidores)
    elif plugin == 'check_db':
        result = plugins.database.check_db(db)
    return result

def gestion_opciones(opciones):
    database = BBDD
    fichero = FICHERO
    contrasenyas = CONTRASENYAS
    servidores = obtener_lista(fichero, contrasenyas, opciones[0])
    result = aplica_plugin(opciones[1], database, servidores)
    return result

def main():
    opciones = leer_parametros()
    result = gestion_opciones(opciones)

    if not result:
        print('Errores en la ejecución del plugin: %s'%opciones[1])
    else:
        print('Ejecución del plugin "%s" correcta.' %opciones[1])

if __name__ == '__main__':
    main()
