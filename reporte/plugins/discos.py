from subprocess import check_output
from re import compile as C, IGNORECASE, match

import plugins.database

TABLAS = {}

TABLAS['discos'] = (
        '''CREATE TABLE IF NOT EXISTS `discos` (
            `fecha` DATETIME DEFAULT CURRENT_TIMESTAMP,
            `alias` VARCHAR(60) NOT NULL,
            `dispositivo` VARCHAR(100) NOT NULL,
            `montaje` VARCHAR(100) NOT NULL,
            `tamanyo` INT(12) NOT NULL,
            `fs_usado` INT(12) NOT NULL,
            `inodos` INT(12) NOT NULL,
            `i_usados` INT(12) NOT NULL,
            FOREIGN KEY (`alias`) REFERENCES `servidores` (`alias`),
            PRIMARY KEY (`fecha`, `alias`)
        ) ENGINE=InnoDB'''
        )

def initDB(database):
    tablas = TABLAS
    result = plugins.database.comprobar_tabla(database, 'discos')
    if not result:
        plugins.database.crear_tablas(database, tablas)

def comprueba_fila(linea):
    patron_disco = '/dev/[hsv]d[a-z][0-9]+'
    disco = C(patron_disco)
    if disco.match(linea[0]):
        return linea
    elif linea[-1] == '/':
        return linea
    else:
        return False

def extrae_campos(servidor, datos):
    inserciones = []
    for linea in datos:
        result = comprueba_fila(linea)
        if result:
            diccionario = {
                            'alias' : servidor['alias'],
                            'dispositivo' : linea[0],
                            'montaje' : linea[-1],
                            'tamanyo' : int(linea[1]),
                            'fs_usado' : int(linea[2]),
                            'inodos' : 0,
                            'i_usados' : 0,
                    }
            inserciones.append(diccionario)
    return inserciones

def obtener_datos(db, servidores):
    comando = 'df'
    for servidor in servidores:
        CMD = ssh_cmd(comando, servidor)
        datos = [ linea.decode('utf-8').split() for linea in check_output(CMD, shell=True).splitlines() ]
        datos_a_insertar = {
                             'tabla' : 'discos',
                             'inserciones' : extrae_campos(servidor, datos)
                           }
        plugins.database.inserta_datos(db, datos_a_insertar)
    return True

def espacio_discos(db, servidores):
    initDB(db)
    result = obtener_datos(db, servidores)
    return result

def ssh_cmd(comando, servidor):
    sshcommand = ("sshpass -p '%s' ssh -p%s %s@%s '%s'"
                  %(servidor['pass'], servidor['port'], servidor['user'], servidor['host'], comando))
    return sshcommand

def run(data):
    if data['opts']['plugin_opts'] == 'espacio':
        espacio_discos(data['config']['database'], data['servers'])

def main():
    pass

if __name__ == '__main__':
    main()
