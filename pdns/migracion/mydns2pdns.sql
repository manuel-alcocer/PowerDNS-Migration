USE procedimientos;

DROP PROCEDURE IF EXISTS mydns2pdns;
DROP PROCEDURE IF EXISTS recorredominios;
DROP PROCEDURE IF EXISTS walkdomains;
DROP FUNCTION IF EXISTS insertdomains;
DROP FUNCTION IF EXISTS insertzones;

delimiter //

CREATE OR REPLACE PROCEDURE insertdomains(IN domain VARCHAR(255), OUT targetid INT)
BEGIN
    DECLARE pdnsdomain VARCHAR(255);

    SELECT TRIM(TRAILING '.' FROM domain) INTO pdnsdomain;

    SELECT COUNT(*) FROM pdns.domains
        WHERE name = pdnsdomain
    INTO targetid;

    IF targetid = 0 THEN
        INSERT INTO pdns.domains (name,type) VALUES (pdnsdomain,'MASTER');
    END IF;

    SELECT id FROM pdns.domains
        WHERE name = pdnsdomain
    INTO targetid;
END
//

CREATE OR REPLACE PROCEDURE insertzones(IN targetid INT, OUT result INT)
BEGIN
    SELECT COUNT(domain_id) INTO result FROM pdns.zones
        WHERE domain_id = targetid;

    IF result = 0 THEN
        INSERT INTO pdns.zones (domain_id, owner) VALUES (targetid, 1);
    END IF;

END
//

CREATE OR REPLACE PROCEDURE insertrecord(IN targetid INT,
                                         IN v_name VARCHAR(255),
                                         IN v_type VARCHAR(10),
                                         IN v_content VARCHAR(6400),
                                         IN v_prio INT(11))
BEGIN

END
//

CREATE OR REPLACE PROCEDURE clonerecords(IN sourceid INT,
                                         IN targetid INT,
                                         OUT result INT)
BEGIN
    DECLARE v_name VARCHAR(255);
    DECLARE v_type VARCHAR(10);
    DECLARE v_content VARCHAR(64000);
    DECLARE v_prio INT(11);
    DECLARE since_epoch INT;
    DECLARE v_disabled TINYINT(1);

    DECLARE done INT DEFAULT FALSE;

    DECLARE c_srecords CURSOR FOR
        SELECT name, type, data, aux
            FROM furanetdns.rr
        WHERE zone = sourceid;

        DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET done = TRUE;

    -- Primero me aseguro que en destino no existe ya ese dominio
    DELETE FROM pdns.records WHERE domain_id = targetid;

    OPEN c_srecords;

    get_records: LOOP
        FETCH c_srecords INTO v_name, v_type, v_content, v_prio;
        IF done THEN
            LEAVE get_records;
        END IF;

        IF v_type = 'SOA' THEN
            CALL insertsoa();
        ELSE
            SET since_epoch := SELECT UNIX_TIMESTAMP(NOW());

            INSERT INTO pdns.records (domain_id, name, type, content,
                                      change_date, auth, disabled, prio)
                   VALUES (targetid, v_name, v_type, v_content,
                           since_epoch, 1, 0, v_prio);
        END IF;
    END LOOP;

    CLOSE c_srecords;

END
//

CREATE OR REPLACE PROCEDURE populatepdns(IN sourceid INTEGER,
                                         IN domain VARCHAR(255),
                                         IN soadata VARCHAR(6400),
                                         IN ttl INTEGER,
                                         IN active VARCHAR(2))
BEGIN
    DECLARE targetid INTEGER;
    DECLARE result INTEGER DEFAULT 0;

    -- Inserciones en tablas de PDNS
    CALL insertdomains(domain, targetid);
    CALL insertzones(targetid, result);
    CALL insertrecords(sourceid, soadata, targetid);
END
//

CREATE OR REPLACE PROCEDURE walkdomains(IN LIMITE INT)
BEGIN
    DECLARE v_sourceid INTEGER;
    DECLARE v_domain VARCHAR(255);
    DECLARE v_soadata VARCHAR(64000);
    DECLARE v_finished INTEGER DEFAULT 0;
    DECLARE v_ttl INTEGER;
    DECLARE v_active VARCHAR(2);
    DECLARE i INTEGER DEFAULT 0;

    DECLARE c_domains CURSOR FOR
        SELECT id, origin,
               CONCAT_WS(' ', ns, mbox, serial, refresh, retry, expire, minimum, ttl),
               ttl, active
        FROM furanetdns.soa;

    DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET v_finished = 1;

    OPEN c_domains;

    -- Recorre todos los dominios de la tabla SOA
    get_domains: LOOP
        FETCH c_domains INTO v_sourceid, v_domain, v_soadata, v_ttl, v_active;
        IF v_finished = 1 OR i > LIMITE THEN
            LEAVE get_domains;
        END IF;
        set i := i + 1;

        CALL populatepdns(v_sourceid, v_domain, v_soadata, v_ttl, v_active);

    END LOOP;

    CLOSE c_domains;

    select v_sourceid,v_domain,v_soadata,v_active;
END
//

CREATE OR REPLACE PROCEDURE mydns2pdns()
BEGIN
    CALL walkdomains(50);
END
//


delimiter ;

call mydns2pdns;
