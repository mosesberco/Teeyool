DROP TABLE IF EXISTS test_primary;
DROP TABLE IF EXISTS test_primary_noded;
DROP TABLE IF EXISTS test_primary_vertices_pgr;


create table test_primary as
select * from osm_transport_lines
where type in (
               'motorway', 'motorway_link', 'trunk', 'trunk_link', 'primary', 'primary_link',
               'secondary', 'secondary_link', 'tertiary', 'tertiary_link', 'residential',
               'road', 'unclassified', 'service', 'busway', 'taxiway', 'track'
    ) and ref is not null and ref not like '';




CREATE SEQUENCE if not exists test_primary_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;

ALTER TABLE test_primary
    ALTER COLUMN id SET DEFAULT nextval('test_primary_id_seq');


ALTER TABLE test_primary
    ADD COLUMN source INTEGER, add column target INTEGER;

ALTER TABLE test_primary
    add COLUMN cost INTEGER;

ALTER TABLE test_primary ADD COLUMN z_level integer;
ALTER TABLE test_primary ADD COLUMN reversed_cost INTEGER;

UPDATE test_primary
SET z_level = CASE
                  WHEN bridge = 1 THEN 1     -- Assign z-level 1 for bridges (above ground)
                  WHEN tunnel = 1 THEN -1    -- Assign z-level -1 for tunnels (below ground)
                  ELSE 0                     -- Assign z-level 0 for regular roads (ground level)
    END;


-- UPDATE test_primary
--     SET cost = case
--         when oneway=1 then -1
--         when oneway=0 then ST_Length(ST_Transform(geometry, 3857))
--         else ST_Length(ST_Transform(geometry, 3857))
-- end;
UPDATE test_primary
SET cost = ST_Length(ST_Transform(geometry, 3857));


UPDATE test_primary
SET reversed_cost = ST_Length(ST_Transform(geometry, 3857));



DROP TABLE IF EXISTS relevant_ids;

-- Step 1: Create a table to store IDs of roundabout lines
CREATE TEMP TABLE relevant_ids AS (
    SELECT id, geometry, osm_id
    FROM test_primary
    WHERE tags -> 'junction' = 'roundabout'
);

drop table if exists connected_ids;
-- Step 2: Get all lines that intersect or are within a small distance of the roundabout lines
CREATE TEMP TABLE connected_ids AS (
    SELECT DISTINCT tp.id
    FROM test_primary tp
             JOIN relevant_ids ri
                  ON ST_Intersects(tp.geometry, ri.geometry)  -- Use ST_Intersects to find connected geometries
                      OR ST_DWithin(tp.geometry, ri.geometry, 0.001)  -- Use ST_DWithin for a small distance if necessary
);

-- Step 3: Execute pgr_nodeNetwork using the relevant connected IDs
SELECT pgr_nodeNetwork(
               'test_primary',         -- Table name containing your edges
               0.001,                  -- Tolerance for node snapping (adjust as needed)
               the_geom := 'geometry', -- Name of the geometry column
               rows_where := 'id IN (SELECT id FROM connected_ids)' -- Use connected IDs
       );


-- Step 1: Add necessary columns to the noded table to store data from the original table
ALTER TABLE test_primary_noded
    ADD COLUMN osm_id bigint,
    ADD COLUMN type character varying,
    ADD COLUMN name character varying,
    ADD COLUMN tunnel smallint,
    ADD COLUMN bridge smallint,
    ADD COLUMN oneway smallint,
    ADD COLUMN ref character varying,
    ADD COLUMN z_order integer,
    ADD COLUMN access character varying,
    ADD COLUMN service character varying,
    ADD COLUMN class character varying,
    ADD COLUMN tags hstore,
    ADD COLUMN z_level integer,
    ADD COLUMN cost integer;

UPDATE test_primary_noded tn
SET
    osm_id = tp.osm_id,
    type = tp.type,
    name = tp.name,
    tunnel = tp.tunnel,
    bridge = tp.bridge,
    oneway = tp.oneway,
    ref = tp.ref,
    z_order = tp.z_order,
    access = tp.access,
    service = tp.service,
    class = tp.class,
    tags = tp.tags,
    source = tp.source,
    target = tp.target,
    z_level = tp.z_level,
    cost = tp.cost
FROM test_primary tp
WHERE tn.old_id = tp.id;


-- Insert new rows into test_primary with the generated unique ids and data from test_primary_noded
INSERT INTO test_primary (id, osm_id, type, name, tunnel, bridge, oneway, ref, z_order, access, service, class, tags, geometry, source, target, z_level, cost)
SELECT
    nextval('test_primary_id_seq'),  -- Generate a new unique ID using the sequence (you may have to create a sequence if needed)
    osm_id,                         -- osm_id from test_primary_noded
    type,                           -- type from test_primary_noded
    name,                           -- name from test_primary_noded
    tunnel,                         -- tunnel from test_primary_noded
    bridge,                         -- bridge from test_primary_noded
    oneway,                         -- oneway from test_primary_noded
    ref,                            -- ref from test_primary_noded
    z_order,                        -- z_order from test_primary_noded
    access,                         -- access from test_primary_noded
    service,                        -- service from test_primary_noded
    class,                          -- class from test_primary_noded
    tags,                           -- tags from test_primary_noded
    geometry,                       -- geometry from test_primary_noded
    source,                         -- source from test_primary_noded
    target,                         -- target from test_primary_noded
    z_level,                        -- z_level from test_primary_noded
    cost                            -- cost from test_primary_noded
FROM test_primary_noded tn;


-- Step 4: Delete lines from test_primary that are in connected_ids
DELETE FROM test_primary
WHERE id IN (SELECT id FROM connected_ids);

select pgr_createTopology('test_primary', 0.001, the_geom := 'geometry', clean := 'true');

-- select * from test_primary where osm_id in (87900327, 317811926, 71587);
--
-- select * from test_primary_noded where old_id = 277307;
--
-- select * from test_primary where osm_id = 689508336;





-- UPDATE test_primary
--     SET cost = CASE
--         WHEN ref = '6' then cost * 0.8
--         ELSE cost
-- end;

select * from test_primary
