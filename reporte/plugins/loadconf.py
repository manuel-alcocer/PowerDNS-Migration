from configparser import ConfigParser

def load_config():
    config = ConfigParser()
    try:
        config.read('init.conf')
    except:
        print('''
            ¡¡¡ Error leyendo el fichero de configuración
            ''')
    else:
        return config

def main():
    load_config()

if __name__ == '__main__':
    main()
