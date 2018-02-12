USE procedimientos;

DROP PROCEDURE IF EXISTS mydns2pdns;
DROP PROCEDURE IF EXISTS recorredominios;
DROP PROCEDURE IF EXISTS walkdomains;
DROP FUNCTION IF EXISTS insertdomains;

delimiter //

CREATE OR REPLACE FUNCTION insertdomains(domain VARCHAR(255))
    RETURNS INTEGER DETERMINISTIC
BEGIN
    DECLARE targetid INTEGER;
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

    -- Devuelve el id del domino en la base de datos de PDNS
    RETURN targetid;
END
//

CREATE OR REPLACE FUNCTION insertzones(targetid INTEGER(10))
    RETURNS INTEGER DETERMINISTIC
BEGIN
    DECLARE total INTEGER DEFAULT 0;

    SELECT COUNT(domain_id) INTO total FROM pdns.zones
        WHERE domain_id = targetid;

    IF total = 0 THEN
        INSERT INTO pdns.zones (domain_id, owner) VALUES (targetid, 1);
    END IF;

    -- Devuelve 0 si inserta, 1 si no inserta
    RETURN total;
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
    SELECT insertdomains(domain) INTO targetid;
    SELECT insertzones(targetid) INTO result;

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
