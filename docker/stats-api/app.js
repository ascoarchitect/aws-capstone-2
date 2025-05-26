const express = require('express');
const { Client } = require('pg');
const cors = require('cors');

const app = express();
const PORT = process.env.PORT || 3001;

// Database configuration
const dbConfig = {
  host: process.env.DB_HOST || 'postgres',
  port: process.env.DB_PORT || 5432,
  database: process.env.DB_NAME || 'gamedb',
  user: process.env.DB_USER || 'gameuser',
  password: process.env.DB_PASSWORD || 'gamepass123'
};

// Middleware
app.use(cors());
app.use(express.json());

// Initialize database connection and create table if needed
async function initDatabase() {
  let retries = 5;
  
  while (retries > 0) {
    const client = new Client(dbConfig);
    try {
      await client.connect();
      console.log('Connected to PostgreSQL database');
      
      // Create table if it doesn't exist
      await client.query(`
        CREATE TABLE IF NOT EXISTS game_stats (
          game_name VARCHAR(50) PRIMARY KEY,
          play_count INTEGER DEFAULT 0
        )
      `);
      
      // Insert initial records if they don't exist
      await client.query(`
        INSERT INTO game_stats (game_name, play_count) 
        VALUES ('DOOM', 0), ('CIVILIZATION', 0)
        ON CONFLICT (game_name) DO NOTHING
      `);
      
      console.log('Database initialized successfully');
      await client.end();
      return; // Success, exit the function
    } catch (err) {
      console.error(`Database initialization error (${retries} retries left):`, err.message);
      retries--;
      try {
        await client.end();
      } catch (endErr) {
        // Ignore errors when ending client
      }
      
      if (retries > 0) {
        await new Promise(resolve => setTimeout(resolve, 5000));
      }
    }
  }
  
  console.error('Failed to initialize database after all retries');
}

// API endpoint to get game stats
app.get('/api/stats', async (req, res) => {
  const client = new Client(dbConfig);
  try {
    await client.connect();
    const result = await client.query('SELECT * FROM game_stats ORDER BY game_name');
    res.json(result.rows);
  } catch (err) {
    console.error('Error fetching stats:', err);
    res.status(500).json({ error: 'Failed to fetch stats' });
  } finally {
    await client.end();
  }
});

// API endpoint to increment play count
app.post('/api/play/:game', async (req, res) => {
  const client = new Client(dbConfig);
  const gameName = req.params.game.toUpperCase();
  
  try {
    await client.connect();
    const result = await client.query(
      'UPDATE game_stats SET play_count = play_count + 1 WHERE game_name = $1 RETURNING *',
      [gameName]
    );
    
    if (result.rows.length > 0) {
      res.json(result.rows[0]);
    } else {
      res.status(404).json({ error: 'Game not found' });
    }
  } catch (err) {
    console.error('Error updating play count:', err);
    res.status(500).json({ error: 'Failed to update play count' });
  } finally {
    await client.end();
  }
});

// Health check endpoint
app.get('/health', async (req, res) => {
  const client = new Client(dbConfig);
  try {
    await client.connect();
    await client.query('SELECT 1');
    await client.end();
    res.json({ status: 'healthy', service: 'stats-api' });
  } catch (err) {
    res.status(503).json({ status: 'unhealthy', error: err.message });
  }
});

// Start server
app.listen(PORT, async () => {
  console.log(`Stats API server running on port ${PORT}`);
  await initDatabase();
});