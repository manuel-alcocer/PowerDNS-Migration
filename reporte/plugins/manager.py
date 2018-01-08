import plugins.manager
import plugins.database
import plugins.discos
import plugins.servidores

def run(data):
    db = config['database']['name']
    if opciones['plugin'] == 'discos':
        result = plugins.discos.run(data)
    elif opciones['plugin'] == 'servidores':
        result = plugins.servidores.run(data)
    elif opciones['plugin'] == 'database':
        result = plugins.database.run(data)
    return result

def main():
    pass

if __name__ == '__main__':
    main()
