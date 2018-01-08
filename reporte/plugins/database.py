from mysql.connector import connect, errorcode, Error

TABLAS = {}

TABLAS['servidores'] = (
        '''CREATE TABLE IF NOT EXISTS `servidores` (
            `alias` varchar(60) NOT NULL,
            `hostname` varchar(100) NOT NULL,
            PRIMARY KEY (`alias`)
        ) ENGINE=InnoDB'''
        )

def abre_conexion(db):
    cnx = connect(user=db['user'], password=db['pass'],
                  host=db['host'], database=db['db'])
    return cnx

def crear_tablas(db, tablas):
    cnx = abre_conexion(db)
    for tabla in tablas.keys():
        try:
            print('Creando tabla {}: '.format(tabla), end='')
            cursor = cnx.cursor()
            cursor.execute(tablas[tabla])
        except Error as err:
            if err.errno == errorcode.ER_TABLE_EXISTS_ERROR:
                print('Tabla ya existe')
            else:
                print(err)
        else:
            print('Tabla creadas con éxito')
    cursor.close()
    cnx.close()

def comprobar_tabla(db, tabla):
    database = db['db']
    cnx = abre_conexion(db)
    cursor = cnx.cursor(dictionary=True)
    query = """SELECT count(*) AS cuenta
               FROM information_schema.tables
               WHERE table_schema = '%s'
               AND table_name = '%s';"""%(database, tabla)
    cursor.execute(query)
    for row in cursor:
        if row['cuenta'] > 0:
            return True
        else:
            return False

def formatea(datos):
    columnas = []
    valores = []
    for insercion in datos['inserciones']:
        (cols, vals) = zip(*insercion.items())
        columnas += [tuple(cols)]
        valores += [tuple(vals)]
    return [columnas, valores]

def inserta_datos(db, datos):
    lista = formatea(datos)
    cnx = abre_conexion(db)
    cursor = cnx.cursor()
    for insercion in lista[1]:
        campos = '{}'.format(lista[0][0]).replace("'",'`')
        valores = '{}'.format(insercion)
        DML = 'INSERT INTO `%s` %s VALUES %s;'%(datos['tabla'], campos, valores)
        print(DML)
        cursor.execute(DML)
    cursor.close()
    cnx.close()

def check_db(db):
    tablas_princ = TABLAS
    try:
        cnx = connect(user=db['user'], password=db['pass'],
                      host=db['host'], database=db['db'])
    except Error as err:
        if err.errno == errorcode.ER_ACCESS_DENIED_ERROR:
            print('''
            ¡¡¡ Error en las credenciales !!!
''')
        elif err.errno == errorcode.ER_BAD_DB_ERROR:
            print('''
            ¡¡¡ No existe la base de datos !!!
''')
        else:
            print('''
            %s
'''%err)
        exit(2)
    else:
        cnx.close()
        print('''
        ¡¡¡ Conexión correcta !!!
''')
        result = comprobar_tabla(db, 'servidores')
        if not result:
            crear_tablas(db, tablas_princ)
        else:
            print('Existe la tabla servidores')
        return True

if __name__ == '__main__':
    main()
