const sql = require('mssql');
const config = require('./config');

async function run() {
  try {
    const pool = await sql.connect(config);
    console.log('Connected to DB');

    // Add CanAdminAssignCustomers
    try {
      await pool.request().query(`
        ALTER TABLE gen_salesmanUseRights
        ADD CanAdminAssignCustomers BIT NOT NULL DEFAULT 0
      `);
      console.log('Added CanAdminAssignCustomers');
    } catch (e) {
      console.log('CanAdminAssignCustomers might already exist or error:', e.message);
    }

    // Add CanAdminUserRights
    try {
      await pool.request().query(`
        ALTER TABLE gen_salesmanUseRights
        ADD CanAdminUserRights BIT NOT NULL DEFAULT 0
      `);
      console.log('Added CanAdminUserRights');
    } catch (e) {
      console.log('CanAdminUserRights might already exist or error:', e.message);
    }

    console.log('Migration done.');
    process.exit(0);
  } catch (err) {
    console.error('Migration failed:', err);
    process.exit(1);
  }
}

run();
