import plugins.manager
import plugins.database
import plugins.discos
import plugins.servidores

def run(config, opciones, servidores):
    db = config['database']['name']
    if opciones['plugin'] == 'discos':
        result = plugins.discos.espacio_discos(db, servidores)
    elif opciones['plugin'] == 'servidores':
        result = plugins.poblar_servidores(db, servidores)
    elif opciones['plugin'] == 'database':
        result = plugins.database.check_db(db)
    return result

def main():
    pass

if __name__ == '__main__':
    main()
