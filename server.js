const express = require('express');
const { Pool } = require('pg');
const path = require('path');

const app = express();
const pool = new Pool({
    user: 'mosesberco', // Update this to your actual PostgreSQL username
    host: 'localhost',
    database: 'israel', // Make sure this database exists
    password: '', // Update this to your actual PostgreSQL password, if you have one
    port: 5432,
});

// Middleware to parse JSON requests
app.use(express.json());

// Serve static files from the public directory
app.use(express.static(path.join(__dirname, '../public')));

// Route to get street names based on coordinates
app.post('/getStreetNames', async (req, res) => {
    const { startCoords, endCoords } = req.body;
    
    console.log("start - ", startCoords, "end - ", endCoords);

    // Implement the logic to get street names based on coordinates
    try {
        const result = await pool.query(`
            WITH closest_first_point AS (
                SELECT 
                    id AS node_id
                FROM 
                    intersection_points
                ORDER BY 
                    geometry <-> ST_Transform(ST_SetSRID(ST_MakePoint($1, $2), 4326), 3857)
                LIMIT 1
            ),
            closest_second_point AS (
                SELECT 
                    id AS node_id
                FROM 
                    intersection_points
                ORDER BY 
                    geometry <-> ST_Transform(ST_SetSRID(ST_MakePoint($3, $4), 4326), 3857)
                LIMIT 1
            )
            SELECT 
                transport_lines.name, 
                transport_lines.id, 
                fp.node_id AS first_point_node_id,
                sp.node_id AS second_point_node_id
            FROM 
                transport_lines
            CROSS JOIN closest_first_point fp
            CROSS JOIN closest_second_point sp
            WHERE 
                ST_DWithin(
                    transport_lines.geometry, 
                    ST_Transform(ST_SetSRID(ST_MakePoint($1, $2), 4326), 3857), 
                    0.1
                )
                OR ST_DWithin(
                    transport_lines.geometry, 
                    ST_Transform(ST_SetSRID(ST_MakePoint($3, $4), 4326), 3857), 
                    0.1
                );

            `, 
            [startCoords[0], startCoords[1], endCoords[0], endCoords[1]]
        );  
        console.log("--------------------------------")
        console.log(result);
        
        const streetNames = result.rows.map(row => row.name);
        res.json({ streetNames });
    } catch (err) {
        console.error(err);
        res.status(500).send('Internal Server Error');
    }
});

// Route to handle shortest-path calculation
app.post('/find-path', async (req, res) => {
    const { points } = req.body; // [[lng1, lat1], [lng2, lat2]]
    if (!points || points.length !== 2) {
        return res.status(400).send({ error: 'Invalid points data' });
    }

    const [[lon1, lat1], [lon2, lat2]] = points;
    console.log("all the lon and lat");
    console.log(lon1, lat1, lon2, lat2);

    try {
        // Find the closest lines to both points
        const closestLineQuery = `
            WITH closest_first_point AS (
                SELECT 
                    source, -- Use the source point of the closest line
                    target,
                    geometry
                FROM test_primary
                ORDER BY geometry <-> ST_Transform(ST_SetSRID(ST_MakePoint($1, $2), 4326), 3857)
                LIMIT 1
            ),
            closest_second_point AS (
                SELECT 
                    source, -- Use the source point of the closest line
                    target,
                    geometry
                FROM test_primary
                ORDER BY geometry <-> ST_Transform(ST_SetSRID(ST_MakePoint($3, $4), 4326), 3857)
                LIMIT 1
            )
            SELECT 
                fp.target AS source_start, 
                sp.source AS source_end
            FROM closest_first_point fp, closest_second_point sp;
        `;

        const closestLineResult = await pool.query(closestLineQuery, [lon1, lat1, lon2, lat2]);
        if (closestLineResult.rowCount === 0) {
            return res.status(404).send({ error: 'No lines found nearby' });
        }

        const { source_start, source_end } = closestLineResult.rows[0];
        console.log(source_start, source_end);

        // Calculate the shortest path using Dijkstra
        const pathQuery = `
            WITH path AS (
                SELECT
                    d.seq,
                    d.path_seq,
                    d.node,
                    d.edge,
                    l.geometry
                FROM
                    pgr_dijkstra(
                        'SELECT id, source, target, cost
                        FROM test_primary',  
                        $1::integer,  -- Start node ID
                        $2::integer,  -- End node ID
                        directed := false
                    ) AS d
                    JOIN test_primary AS l
                        ON d.edge = l.id
                ORDER BY d.seq
            ),
            path_geometry AS (
                SELECT ST_Union(geometry) AS full_path_geometry
                FROM path
            )
            SELECT 
                ST_AsGeoJSON(ST_Transform(full_path_geometry, 4326)) AS path_geometry,
                ST_Length(ST_Transform(full_path_geometry, 4326)::geography) AS path_length_meters
            FROM path_geometry;
        `;

        const pathResult = await pool.query(pathQuery, [source_start, source_end]);
        if (pathResult.rowCount === 0) {
            return res.status(404).send({ error: 'No path found' });
        }

        // Extract geometry and length from the query result
        const { path_geometry, path_length_meters } = pathResult.rows[0];

        const parsedGeometry = JSON.parse(path_geometry);
        const averageSpeedMetersPerSecond = 16.67; // Example speed: 60 km/h
        const travelTimeSeconds = path_length_meters / averageSpeedMetersPerSecond;

        // Send the response
        res.send({
            geometry: parsedGeometry,                // GeoJSON LineString
            length: path_length_meters.toFixed(2),  // Length in meters
            time: travelTimeSeconds.toFixed(2),     // Travel time in seconds
        });
    } catch (err) {
        console.error('Error in /find-path:', err);
        res.status(500).send({ error: 'Internal server error' });
    }
});





// Start the server
app.listen(8000, () => {
    console.log('Server is running on http://localhost:8000');
});


// Make sure you have a file like 'index.html' in the 'public' directory
app.get('/', (req, res) => {
    res.sendFile(path.join(__dirname, '../teeyool/public/index.html'));
});
