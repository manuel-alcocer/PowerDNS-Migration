/*
    Procedimientos para migrar de MyDNS -> PowerDNS

    Código por:         Manuel Alcocer Jiménez
    freenode.#birras:   nashgul
    mail:               manuel@alcocer.net

*/

USE procedimientos;

-- Desactivo los TRIGGERS para ganar un poco de velocidad
-- en la migración
-- Al final se vuelven a activar
SET @TRIGGER_CHECKS = FALSE;

delimiter //

/* Procedimiento para reiniciar la migración
*/

CREATE OR REPLACE PROCEDURE limpia()
BEGIN

    DELETE FROM pdns.domains;
    ALTER TABLE pdns.domains AUTO_INCREMENT = 1;

    DELETE FROM pdns.zones;
    ALTER TABLE pdns.zones AUTO_INCREMENT = 1;

    DELETE FROM pdns.records;
    ALTER TABLE pdns.records AUTO_INCREMENT = 1;
END
//

/* Procedimiento para quitar de forma condicionada
 * los puntos al final de los registros de tipo TEXTO
 * Devuelve 1 si considera que no se debe insertar por
 * estar mal formado
*/

CREATE OR REPLACE PROCEDURE check_name_record (p_origin VARCHAR(255),
                                               INOUT p_name VARCHAR(255),
                                               OUT p_act INTEGER)
BEGIN
    SET p_act = 0;
    IF (LENGTH(p_name) = 1 AND p_name = '@') OR LENGTH(p_name) = 0 THEN
        SELECT CONCAT(p_origin, '.') INTO p_name;
    ELSEIF LENGTH(p_name) = 1 AND p_name = '.' THEN
        SET p_act = 1;
    END IF;

    IF SUBSTR(p_name, -1) != '.' THEN
        SELECT CONCAT(p_name, '.', p_origin, '.') INTO p_name;
    END IF;

    SELECT TRIM(TRAILING '.' FROM p_name) INTO p_name;
END
//

/* los TXT necesitan ir encerrados entre comillas */

CREATE OR REPLACE PROCEDURE check_txt_record (INOUT p_content VARCHAR(64000))
BEGIN
    IF SUBSTR(p_content, 1, 1) != '\"' THEN
        SELECT CONCAT('\"', p_content) INTO p_content;
    END IF;

    IF SUBSTR(p_content, -1 ,1) != '\"' THEN
        SELECT CONCAT(p_content, '\"') INTO p_content;
    END IF;
END
//

/* Procedimiento que chequea el registro content de PDNS */

CREATE Or REPLACE PROCEDURE check_content (p_type VARCHAR(10),
                                           p_origin VARCHAR(255),
                                           INOUT p_content VARCHAR(64000))
BEGIN
    DECLARE v_act INTEGER;
    IF p_type IN ('CNAME', 'NS', 'MX', 'PTR') THEN
        CALL check_name_record (p_origin, p_content, v_act);
    ELSEIF p_type = 'TXT' THEN
        CALL check_txt_record (p_content);
    END IF;
END
//

/* Devuelve 0 si no existe la zona en la BBDD pdns */
CREATE OR REPLACE PROCEDURE check_if_zone (p_origin VARCHAR(255),
                                           OUT p_result INTEGER)
BEGIN
    DECLARE v_mydns_serial INTEGER DEFAULT 0;
    DECLARE v_pdns_serial INTEGER DEFAULT 0;

    SELECT count(*) INTO p_result
    FROM pdns.domains
    WHERE name = TRIM(TRAILING '.' FROM p_origin);

    -- si existe en destino, comprueba serials
    IF p_result > 0 THEN
        SELECT serial INTO v_mydns_serial
        FROM furanet.soa
        WHERE origin = p_origin;

        SELECT IFNULL(REGEXP_REPLACE(content, '(\\S+\\s+){2}(\\S+\\s+).*', '\\2'), 0)
            INTO v_pdns_serial
        FROM pdns.records
            WHERE name = TRIM(TRAILING '.' FROM p_origin)
            AND type = 'SOA';
        IF v_mydns_serial > v_pdns_serial THEN
            SET p_result = 2;
        ELSE
            SET p_result = 0;
        END IF;
    ELSE
        SET p_result = 1;
    END IF;
END
//

/* Procedimiento que pasa los registros de un id de origen
 * a un domain_id de destino
 */
CREATE OR REPLACE PROCEDURE clone_records (p_zone_id INTEGER,
                                           p_domain_id INTEGER,
                                           p_origin VARCHAR(255))
BEGIN
    DECLARE v_name VARCHAR(255);
    DECLARE v_type VARCHAR(10);
    DECLARE v_content VARCHAR(64000);
    DECLARE v_prio INTEGER;
    DECLARE v_ttl INTEGER;
    DECLARE v_change_date INTEGER;

    DECLARE v_act INTEGER DEFAULT 0;

    DECLARE v_done INT DEFAULT FALSE;

    DECLARE c_records CURSOR FOR
        SELECT name, type, data, aux, ttl, UNIX_TIMESTAMP(NOW())
        FROM furanet.rr
            WHERE zone = p_zone_id;

    DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_done = TRUE;

    OPEN c_records;
    get_records: LOOP

        FETCH c_records
            INTO v_name, v_type, v_content, v_prio, v_ttl, v_change_date;

        IF v_done THEN
            LEAVE get_records;
        END IF;

        CALL check_name_record (p_origin, v_name, v_act);
        CALL check_content (v_type, p_origin, v_content);

        IF v_act = 0 THEN
            INSERT INTO pdns.records (domain_id, name, type, content,
                                      ttl, prio, change_date)
                   VALUES (p_domain_id, v_name, v_type, v_content,
                           v_ttl, v_prio, v_change_date);
        END IF;

    END LOOP;
    CLOSE c_records;
END
//

/* zoneid: identificador de zona en origen
 * zone_origin: dominio acabado en '.': example.org.
*/

/* Clonado del registro SOA */
CREATE OR REPLACE PROCEDURE clone_soa (p_zone_id INTEGER,
                                       p_domain_id INTEGER,
                                       OUT p_name VARCHAR(255))
BEGIN
    DECLARE v_content VARCHAR(64000);
    DECLARE v_ttl INTEGER;
    DECLARE v_change_date INTEGER;
    DECLARE v_disabled TINYINT(1) DEFAULT 0;
    DECLARE v_active VARCHAR(2);

    -- Primero me aseguro que en destino no existe ya ese dominio
    DELETE FROM pdns.records WHERE domain_id = p_domain_id;

    SELECT TRIM(TRAILING '.' FROM origin),
           CONCAT_WS(' ', TRIM(TRAILING '.' FROM ns),
                     TRIM(TRAILING '.' FROM mbox),
                     serial, refresh, retry, expire, minimum),
           ttl, active, UNIX_TIMESTAMP(NOW())
    INTO p_name, v_content, v_ttl, v_active, v_change_date
    FROM furanet.soa
    WHERE id = p_zone_id;

    IF v_active = 'N' THEN
        SET v_disabled = 1;
    END IF;

    INSERT
        INTO pdns.records
            (domain_id, name, type, content, ttl, prio, change_date, disabled, auth)
        VALUES
            (p_domain_id, p_name, 'SOA', v_content, v_ttl, 0, v_change_date, v_disabled, 1);
END
//

CREATE OR REPLACE PROCEDURE insert_zone (p_domain_id INTEGER)
BEGIN
    DECLARE v_domain_id INTEGER;

    SELECT COUNT(*) INTO v_domain_id FROM pdns.zones
        WHERE domain_id = p_domain_id;

    IF v_domain_id = 0 THEN
        INSERT INTO pdns.zones (domain_id, owner) VALUES (p_domain_id, 1);
    END IF;
END
//

/* Crea el registro de la zona correspondiente en la tabla DOMAINS */

CREATE OR REPLACE PROCEDURE insert_domain (p_zone_id INTEGER,
                                           OUT p_domain_id INTEGER)
BEGIN
    DECLARE v_name VARCHAR(255);

    SELECT TRIM(TRAILING '.' FROM origin) INTO v_name FROM furanet.soa
        WHERE id = p_zone_id;

    SELECT COUNT(*) INTO p_domain_id FROM pdns.domains
        WHERE name = v_name;

    IF p_domain_id = 0 THEN
        INSERT INTO pdns.domains (name, type) VALUES (v_name, 'NATIVE');
    END IF;

    SELECT id INTO p_domain_id FROM pdns.domains
        WHERE name = v_name;
END
//

/* Dado un identificador de zona de origen, lo clona completo en PDNS */
CREATE OR REPLACE PROCEDURE clone_zone (p_zone_id INTEGER,
                                        p_origin VARCHAR(255))
BEGIN
    DECLARE v_domain_id INTEGER;
    DECLARE v_name VARCHAR(255);
    DECLARE v_result INTEGER DEFAULT 0;

    CALL check_if_zone(p_origin, v_result);
    IF v_result <> 0 THEN
        CALL insert_domain (p_zone_id, v_domain_id);
        CALL insert_zone (v_domain_id);
        CALL clone_soa (p_zone_id, v_domain_id, v_name);
        CALL clone_records (p_zone_id, v_domain_id, v_name);
    END IF;
    SET @result := v_result;
END
//

/* Recorre todas las zonas de origen */
CREATE OR REPLACE PROCEDURE walk_domains (INOUT p_limit INT)
BEGIN
    DECLARE v_zone_id INTEGER;
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE v_origin VARCHAR(255);
    DECLARE i INTEGER DEFAULT 0;

    DECLARE c_domains CURSOR FOR
        SELECT id, origin FROM furanet.soa
        ORDER BY id;

    DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_done = TRUE;

    IF p_limit = 0 THEN
        SELECT COUNT(id) INTO p_limit
        FROM furanet.soa;
    END IF;

    OPEN c_domains;
    get_domains: LOOP
        SET v_zone_id = 0;

        FETCH c_domains INTO v_zone_id, v_origin;

        IF v_done OR i > p_limit THEN
            LEAVE get_domains;
        END IF;

        SET i = i + 1;

        SELECT 'Insertando', v_origin;
        CALL clone_zone (v_zone_id, v_origin);
        IF @result = 0 THEN
            SELECT 'Se saltó', v_origin;
        END IF;

    END LOOP;
    CLOSE c_domains;

END
//

/* clona los registros que cumplan con un patron dado en formato SQL LIKE */
CREATE OR REPLACE PROCEDURE clone_patron(p_patron VARCHAR(255))
BEGIN
    DECLARE v_done INTEGER DEFAULT FALSE;
    DECLARE total INTEGER DEFAULT 0;
    DECLARE v_id VARCHAR(255);
    DECLARE num INTEGER DEFAULT 0;

    DECLARE c_search CURSOR FOR
        SELECT id, (
                    SELECT COUNT(id) FROM furanet.soa
                        WHERE origin LIKE p_patron
                    )
        FROM furanet.soa
            WHERE origin LIKE p_patron;

    DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_done = TRUE;

    OPEN c_search;

    walk_result: LOOP
        FETCH c_search INTO v_id, total;
        SET num = num + 1;
        IF v_done THEN
            LEAVE walk_result;
        END IF;

        CALL clone_zone(num, total, v_id);

    END LOOP;
    CLOSE c_search;
END
//

CREATE OR REPLACE PROCEDURE mydns2pdns(p_limite INTEGER)
BEGIN
    CALL walk_domains(p_limite);
END
//

DELIMITER ;

USE pdns;

DELIMITER //

-- Trigger para tener actualizado el change_date en caso de inserción
CREATE OR REPLACE TRIGGER insert_change_date
BEFORE INSERT ON records FOR EACH ROW
BEGIN
    SET NEW.change_date = UNIX_TIMESTAMP(NOW());
END
//

-- Trigger para tener actualizado el change_date en caso de actualización
CREATE OR REPLACE TRIGGER update_change_date
BEFORE UPDATE ON records FOR EACH ROW
BEGIN
    SET NEW.change_date = UNIX_TIMESTAMP(NOW());
END
//

DELIMITER ;

USE furanet;

DELIMITER //

CREATE OR REPLACE TRIGGER update_zone
AFTER UPDATE ON soa FOR EACH ROW
BEGIN
    CALL procedimientos.clone_zone(NEW.id, NEW.origin);
END
//

DELIMITER ;
-- Clona 25 registros
-- call mydns2pdns(25);

-- Clona todos registros
-- call mydns2pdns(0);

-- Vuelvo a activar los triggers
SET @TRIGGER_CHECKS = TRUE;

USE procedimientos;

