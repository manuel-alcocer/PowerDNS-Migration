/*
    Procedimientos para migrar de MyDNS -> PowerDNS

    Código por:         Manuel Alcocer Jiménez
    freenode.#birras:   nashgul
    mail:               manuel@alcocer.net

*/

USE procedimientos;

delimiter //

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

CREATE OR REPLACE PROCEDURE check_name_record (p_origin VARCHAR(255),
                                               INOUT p_name VARCHAR(255),
                                               OUT p_act INTEGER)
BEGIN
    set p_act := 0;
    IF (LENGTH(p_name) = 1 AND p_name = '@') OR LENGTH(p_name) = 0 THEN
        SELECT CONCAT(p_origin, '.') INTO p_name;
    ELSEIF LENGTH(p_name) = 1 AND p_name = '.' THEN
        set p_act := 1;
    END IF;

    IF SUBSTR(p_name, -1) != '.' THEN
        SELECT CONCAT(p_name, '.', p_origin, '.') INTO p_name;
    END IF;

    SELECT TRIM(TRAILING '.' FROM p_name) INTO p_name;
END
//

CREATE Or REPLACE PROCEDURE check_content (p_type VARCHAR(10),
                                           p_origin VARCHAR(255),
                                           INOUT p_content VARCHAR(64000))
BEGIN
    DECLARE v_act INTEGER;
    IF p_type IN ('CNAME', 'NS', 'MX', 'PTR') THEN
        CALL check_name_record (p_origin, p_content, v_act);
    END IF;
END
//

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
           CONCAT_WS(' ', ns, mbox, serial, refresh, retry, expire, minimum, ttl),
           ttl, active, UNIX_TIMESTAMP(NOW())
    INTO p_name, v_content, v_ttl, v_active, v_change_date
    FROM furanet.soa
    WHERE id = p_zone_id;

    IF v_active = 'N' THEN
        set v_disabled := 1;
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

CREATE OR REPLACE PROCEDURE insert_domain (p_zone_id INTEGER,
                                           OUT p_domain_id INTEGER)
BEGIN
    DECLARE v_name VARCHAR(255);

    SELECT TRIM(TRAILING '.' FROM origin) INTO v_name FROM furanet.soa
        WHERE id = p_zone_id;

    SELECT COUNT(*) INTO p_domain_id FROM pdns.domains
        WHERE name = v_name;

    IF p_domain_id = 0 THEN
        INSERT INTO pdns.domains (name, type) VALUES (v_name, 'MASTER');
    END IF;

    SELECT id INTO p_domain_id FROM pdns.domains
        WHERE name = v_name;
END
//

CREATE OR REPLACE PROCEDURE clone_zone (num INTEGER,
                                        p_zone_id INTEGER)
BEGIN
    DECLARE v_domain_id INTEGER;
    DECLARE v_name VARCHAR(255);
    DECLARE insertando VARCHAR(255);

    CALL insert_domain (p_zone_id, v_domain_id);
    CALL insert_zone (v_domain_id);
    CALL clone_soa (p_zone_id, v_domain_id, v_name);
    SET insertando := v_name;
    SELECT num, insertando, v_domain_id;
    CALL clone_records (p_zone_id, v_domain_id, v_name);
END
//

CREATE OR REPLACE PROCEDURE walk_domains (INOUT p_limite INT)
BEGIN
    DECLARE v_zone_id INTEGER;
    DECLARE v_done INT DEFAULT FALSE;
    DECLARE i INTEGER DEFAULT 0;

    DECLARE c_domains CURSOR FOR
        SELECT id FROM furanet.soa;

    DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_done = TRUE;

    IF p_limite = 0 THEN
        SELECT COUNT(id) INTO p_limite
        FROM furanet.soa;
    END IF;

    OPEN c_domains;
    get_domains: LOOP

        FETCH c_domains INTO v_zone_id;

        IF v_done OR i > p_limite THEN
            LEAVE get_domains;
        END IF;

        set i := i + 1;
        CALL clone_zone (i, v_zone_id);

    END LOOP;
    CLOSE c_domains;

END
//

CREATE OR REPLACE PROCEDURE mydns2pdns(p_limite INTEGER)
BEGIN
    CALL walk_domains(p_limite);
END
//


delimiter ;

-- call mydns2pdns();
