# Resincronizar
https://stackoverflow.com/questions/2366018/how-to-re-sync-the-mysql-db-if-master-and-slave-have-different-database-incase-o
# Mejor esto: https://www.howtoforge.com/tutorial/how-to-install-and-configure-galera-cluster-on-ubuntu-1604/

# Instalación de servicios

```
root@cmv-pdns1:~# apt install mariadb-server pdns-server pdns-tools pdns-recursor pdns-backend-mysql
root@cmv-pdns2:~# apt install mariadb-server pdns-server pdns-tools pdns-recursor pdns-backend-mysql
```

## Configuración de MariaDB

https://mariadb.com/kb/en/library/configuring-mariadb-for-remote-client-access/
https://linode.com/docs/databases/mysql/configure-master-master-mysql-database-replication/

Añadir esta línea al servicio '/etc/systemd/system/mariadb.service':
```
root@cmv-pdns2:~# systemctl edit --full mariadb.service

Environment="MYSQLD_OPTS=--log-bin --log-basename=nombre"
```

Fichero '/etc/mysql/mariadb.conf.d/50-server.cnf':
(El id debe ser único para cada servidor)

### Servidor 1

```
[mysqld]
log_bin                 = /var/log/mysql/mysql-bin.log
log_basename            = pdns1     # ponerhostname

[mariadb]
server_id=1
auto-increment-offset = 1
# Este valor corresponde con el número de nodos (como mínimo)
# https://mariadb.org/auto-increments-in-galera/
auto-increment-increment = 2
```

### Servidor 2

```
[mysqld]
log_bin                 = /var/log/mysql/mysql-bin.log
log_basename            = pdns2     # ponerhostname

[mariadb]
server_id=2
auto-increment-offset = 2
# Este valor corresponde con el número de nodos (como mínimo)
# https://mariadb.org/auto-increments-in-galera/
auto-increment-increment = 2
```

REINICIAR MYSQL en ambos servidores

### Servidor 1:
mysql:
```
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%' identified by 'replicator';
flush privileges;

MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| pdns1-bin.000004 |      626 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.00 sec)

MariaDB [(none)]>
```

### Servidor 2:
mysql:
```
GRANT REPLICATION SLAVE ON *.* TO 'replicator'@'%' identified by 'replicator';
flush privileges;

MariaDB [(none)]> show master status;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| pdns2-bin.000004 |      626 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.00 sec)

MariaDB [(none)]>
```
### Servidor 2
```
mysql:
stop slave;
change master to master_host='10.0.100.21', master_port=3306, master_user='replicator', master_password='replicator', master_log_file='pdns1-bin.000004', master_log_pos=626;
start slave;
MariaDB [(none)]> SHOW MASTER STATUS;
+------------------+----------+--------------+------------------+
| File             | Position | Binlog_Do_DB | Binlog_Ignore_DB |
+------------------+----------+--------------+------------------+
| pdns2-bin.000003 |      626 |              |                  |
+------------------+----------+--------------+------------------+
1 row in set (0.00 sec)

MariaDB [(none)]>
```

### Servidor 1
```
mysql:
stop slave;
change master to master_host='10.0.100.8', master_port=3306, master_user='replicator2', master_password='replicator2', master_log_file='pdns2-bin.000003', master_log_pos=626;
start slave;
```




