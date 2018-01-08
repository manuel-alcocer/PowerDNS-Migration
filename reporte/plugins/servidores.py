from yaml import dump as dyml, load as lyml

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

def init(config, opciones):
    fichero_hosts = config['DEFAULT']['fichero_hosts']
    fichero_pass = config['DEFAULT']['fichero_pass']
    servidores = obtener_lista(fichero_hosts, fichero_pass, opciones['tag'])
    
    return servidores
