USE procedimientos;

DROP PROCEDURE IF EXISTS mydns2pdns;
DROP PROCEDURE IF EXISTS recorredominios;
DROP PROCEDURE IF EXISTS walkdomains;
DROP FUNCTION IF EXISTS insertdomain;

delimiter //

CREATE OR REPLACE FUNCTION insertdomain(domain VARCHAR(255))
    RETURNS INTEGER DETERMINISTIC
BEGIN
    DECLARE targetid INTEGER;
    DECLARE pdnsdomain VARCHAR(255);
    
    SELECT TRIM(TRAILING '.' FROM domain) INTO pdnsdomain;

    SELECT COUNT(*) FROM pdns.domains
        WHERE name = pdnsdomain
    INTO targetid;

    IF targetid = 0 THEN
        INSERT INTO pdns.domains (name,type) VALUES(pdnsdomain,'MASTER');
        SELECT id FROM pdns.domains
            WHERE name = pdnsdomain
        INTO targetid;
        RETURN targetid;
    ELSE
        RETURN 0;
    END IF;
END//

CREATE OR REPLACE PROCEDURE walkdomains(IN LIMITE INT)
BEGIN
    DECLARE v_sourceid INTEGER;
    DECLARE v_domain VARCHAR(255);
    DECLARE v_soadata VARCHAR(64000);
    DECLARE v_finished INTEGER DEFAULT 0;
    DECLARE v_ttl INTEGER;
    DECLARE v_active VARCHAR(2);
    DECLARE targetid INTEGER;
    DECLARE i INTEGER DEFAULT 0;

    DECLARE c_domains CURSOR FOR
        SELECT id,origin,CONCAT_WS(' ',ns,mbox,serial,refresh,retry,expire,minimum,ttl),
                ttl,active
        FROM furanetdns.soa;

    DECLARE CONTINUE HANDLER 
        FOR NOT FOUND SET v_finished = 1;

    -- Recorre todos los dominios de la tabla SOA
    OPEN c_domains;
    get_domains: LOOP
        FETCH c_domains INTO v_sourceid, v_domain, v_soadata, v_ttl, v_active;
        IF v_finished = 1 OR i > LIMITE THEN
            LEAVE get_domains;
        END IF;
        set i := i + 1;
        -- select sourceid,domain,soadata,active;
        SELECT insertdomain(v_domain) INTO targetid;
        SELECT targetid;
    END LOOP;
    CLOSE c_domains;
    select v_sourceid,v_domain,v_soadata,v_active;
END//

CREATE OR REPLACE PROCEDURE mydns2pdns()
BEGIN
    CALL walkdomains(50);
END//



delimiter ;

call mydns2pdns;
