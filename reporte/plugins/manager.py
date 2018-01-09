import plugins.manager
import plugins.database
import plugins.discos
import plugins.servidores

def run(data):
    db = data['config']['database']
    if data['opts']['plugin'] == 'discos':
        result = plugins.discos.run(data)
    elif data['opts']['plugin'] == 'servidores':
        result = plugins.servidores.run(data)
    elif data['opts']['plugin'] == 'database':
        result = plugins.database.run(data)
    return result

def main():
    pass

if __name__ == '__main__':
    main()
