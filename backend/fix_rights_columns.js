const sql = require('mssql');
const config = require('./config');

async function run() {
  try {
    const pool = await sql.connect(config);
    console.log('Connected to DB');

    // Drop old columns
    try {
      await pool.request().query(`
        ALTER TABLE gen_salesmanUseRights
        DROP COLUMN CanAdminAssignCustomers, CanAdminUserRights
      `);
      console.log('Dropped old columns');
    } catch (e) {
      console.log('Drop columns failed:', e.message);
    }

    // Add new columns
    try {
      await pool.request().query(`
        ALTER TABLE gen_salesmanUseRights
        ADD isReporting BIT NOT NULL DEFAULT 0,
            isAssignCustomers BIT NOT NULL DEFAULT 0,
            isUserRights BIT NOT NULL DEFAULT 0
      `);
      console.log('Added new columns');
    } catch (e) {
      console.log('Add columns failed:', e.message);
    }

    console.log('Migration done.');
    process.exit(0);
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  }
}

run();
