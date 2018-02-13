/*
    Procedimientos para migrar de MyDNS -> PowerDNS

    Código por:         Manuel Alcocer Jiménez
    freenode.#birras:   nashgul
    mail:               manuel@alcocer.net

*/

USE procedimientos;

delimiter //

CREATE OR REPLACE FUNCTION checkdnsname(p_origin VARCHAR(255), p_name VARCHAR(255))
    RETURNS VARCHAR(255)
BEGIN
    DECLARE v_name VARCHAR(255);

    IF SUBSTR(p_name, -1) = '.' THEN
        SELECT TRIM(TRAILING '.' FROM p_name) INTO v_name;
    ELSE
        SELECT CONCAT(p_name, '.', p_origin) INTO v_name;
    END IF

    RETURN v_name;
END
//

CREATE OR REPLACE PROCEDURE insertdomains(IN p_domain VARCHAR(255),
                                          OUT p_targetid INT)
BEGIN
    DECLARE v_pdnsdomain_name VARCHAR(255);

    SELECT TRIM(TRAILING '.' FROM p_domain) INTO v_pdnsdomain_name;

    SELECT COUNT(*) FROM pdns.domains
        WHERE name = v_pdnsdomain_name
    INTO p_targetid;

    IF p_targetid = 0 THEN
        INSERT INTO pdns.domains (name,type) VALUES (v_pdnsdomain_name,'MASTER');
    END IF;

    SELECT id FROM pdns.domains
        WHERE name = v_pdnsdomain_name
    INTO p_targetid;
END
//

CREATE OR REPLACE PROCEDURE insertzones(IN p_targetid INT,
                                        OUT p_result INT)
BEGIN
    SELECT COUNT(domain_id) INTO p_result FROM pdns.zones
        WHERE domain_id = p_targetid;

    IF p_result = 0 THEN
        INSERT INTO pdns.zones (domain_id, owner) VALUES (p_targetid, 1);
    END IF;

END
//

CREATE OR REPLACE PROCEDURE clonerecords(IN p_sourceid INT,
                                         IN p_targetid INT,
                                         IN p_domain_name VARCHAR(255),
                                         IN p_soadata VARCHAR(64000),
                                         IN p_ttl INTEGER,
                                         IN p_active VARCHAR(2))
BEGIN
    DECLARE v_name VARCHAR(255);
    DECLARE v_type VARCHAR(10);
    DECLARE v_content VARCHAR(64000);
    DECLARE v_prio INT(11);
    DECLARE v_change_date INT;
    DECLARE v_disabled TINYINT(1) DEFAULT 0;

    DECLARE v_done INT DEFAULT FALSE;

    DECLARE c_srecords CURSOR FOR
        SELECT TRIM(TRAILING '.' FROM name), type, data, aux
            FROM furanetdns.rr
        WHERE zone = p_sourceid;

        DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_done = TRUE;

    IF p_active != 'Y' THEN
        set v_disabled := 1;
    END IF;

    OPEN c_srecords;
    get_records: LOOP

        FETCH c_srecords INTO v_name, v_type, v_content, v_prio;

        IF v_done THEN
            LEAVE get_records;
        END IF;

        IF LENGTH(v_name) = 0 THEN
            SELECT TRIM(TRAILING '.' FROM p_domain_name) INTO v_name;
        END IF;

        SELECT UNIX_TIMESTAMP(NOW()) INTO v_change_date;

        INSERT INTO pdns.records (domain_id, name, type, content,
                                  change_date, auth, disabled, prio)
               VALUES (p_targetid, v_name, v_type, v_content,
                       v_change_date, 1, 0, v_prio);

    END LOOP;
    CLOSE c_srecords;

END
//

CREATE OR REPLACE PROCEDURE insertsoa(IN p_domain_id INTEGER,
                                      IN p_name VARCHAR(255),
                                      IN p_content VARCHAR(64000),
                                      IN p_ttl INTEGER,
                                      IN p_active VARCHAR(2))
BEGIN
    DECLARE v_pdnsdomain_name VARCHAR(255);
    DECLARE v_change_date INTEGER;
    DECLARE v_disabled TINYINT(1) DEFAULT 0;

    -- Primero me aseguro que en destino no existe ya ese dominio
    DELETE FROM pdns.records WHERE domain_id = p_domain_id;

    SELECT UNIX_TIMESTAMP(NOW()) INTO v_change_date;

    SELECT TRIM(TRAILING '.' FROM p_name) INTO v_pdnsdomain_name;

    IF p_active != 'Y' THEN
        set v_disabled := 1;
    END IF;

    INSERT
        INTO pdns.records
            (domain_id, name, type, content, ttl, prio, change_date, auth)
        VALUES
            (p_domain_id, v_pdnsdomain_name, 'SOA', p_content, p_ttl, 0, v_change_date, 1);
END
//

CREATE OR REPLACE PROCEDURE clonezone(IN p_sourceid INTEGER,
                                      IN p_domain VARCHAR(255),
                                      IN p_soadata VARCHAR(64000),
                                      IN p_ttl INTEGER,
                                      IN p_active VARCHAR(2))
BEGIN
    DECLARE v_targetid INTEGER;
    DECLARE v_result INTEGER DEFAULT 0;

    -- Inserciones en tablas de PDNS
    CALL insertdomains(p_domain, v_targetid);
    CALL insertzones(v_targetid, v_result);
    CALL insertsoa(v_targetid, p_domain, p_soadata, p_ttl, p_active);
    CALL clonerecords(p_sourceid, v_targetid, p_domain, p_soadata, p_ttl, p_active);
END
//

CREATE OR REPLACE PROCEDURE walkdomains(IN p_limite INT)
BEGIN
    DECLARE v_sourceid INTEGER;
    DECLARE v_domain VARCHAR(255);
    DECLARE v_soadata VARCHAR(64000);
    DECLARE v_finished INT DEFAULT FALSE;
    DECLARE v_ttl INTEGER;
    DECLARE v_active VARCHAR(2);
    DECLARE i INTEGER DEFAULT 0;

    DECLARE c_domains CURSOR FOR
        SELECT id, origin,
               CONCAT_WS(' ', ns, mbox, serial, refresh, retry, expire, minimum, ttl),
               ttl, active
        FROM furanetdns.soa;

    DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_finished = TRUE;

    OPEN c_domains;
    get_domains: LOOP

        FETCH c_domains INTO v_sourceid, v_domain, v_soadata, v_ttl, v_active;

        IF v_finished OR i > p_limite THEN
            LEAVE get_domains;
        END IF;

        set i := i + 1;

        CALL clonezone(v_sourceid, v_domain, v_soadata, v_ttl, v_active);

    END LOOP;
    CLOSE c_domains;

END
//

CREATE OR REPLACE PROCEDURE mydns2pdns()
BEGIN
    CALL walkdomains(50);
END
//


delimiter ;

call mydns2pdns;
