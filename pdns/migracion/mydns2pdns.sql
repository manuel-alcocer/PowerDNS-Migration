USE procedimientos;

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

    DECLARE done INT DEFAULT FALSE;

    DECLARE c_srecords CURSOR FOR
        SELECT name, type, data, aux
            FROM furanetdns.rr
        WHERE zone = p_sourceid;

        DECLARE CONTINUE HANDLER
        FOR NOT FOUND SET done = TRUE;

    -- Primero me aseguro que en destino no existe ya ese dominio
    DELETE FROM pdns.records WHERE domain_id = p_targetid;

    IF p_active != 'Y' THEN
        set v_disabled := 1;
    END IF;

    OPEN c_srecords;

    get_records: LOOP
        FETCH c_srecords INTO v_name, v_type, v_content, v_prio;

        IF done THEN
            LEAVE get_records;
        END IF;

        IF LENGTH(v_name) = 0 THEN
            set v_name := p_domain_name;
        END IF;

        IF v_type = 'SOA' THEN
            set v_content := p_soadata;
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

CREATE OR REPLACE PROCEDURE populatepdns(IN p_sourceid INTEGER,
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
    CALL insertsoa(p_domain, p_soadata, p_ttl, p_active)
    CALL clonerecords(p_sourceid, v_targetid, p_domain, p_soadata, p_ttl, p_active);
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
END
//

CREATE OR REPLACE PROCEDURE mydns2pdns()
BEGIN
    CALL walkdomains(50);
END
//


delimiter ;

call mydns2pdns;
