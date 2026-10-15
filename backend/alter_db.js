const sql = require('mssql');
const config = require('./config');

async function alterDB() {
  try {
    const pool = await sql.connect(config);
    console.log("Connected to DB. Altering table...");

    // Try to add isApproved
    try {
      await pool.request().query("ALTER TABLE inv_invoiceheader ADD isApproved BIT NOT NULL DEFAULT 0");
      console.log("Added isApproved column.");
    } catch (e) {
      if (e.message.includes('already exists')) console.log("isApproved already exists.");
      else throw e;
    }

    // Try to add isPending
    try {
      await pool.request().query("ALTER TABLE inv_invoiceheader ADD isPending BIT NOT NULL DEFAULT 1");
      console.log("Added isPending column.");
    } catch (e) {
      if (e.message.includes('already exists')) console.log("isPending already exists.");
      else throw e;
    }

    // Try to add isReject
    try {
      await pool.request().query("ALTER TABLE inv_invoiceheader ADD isReject BIT NOT NULL DEFAULT 0");
      console.log("Added isReject column.");
    } catch (e) {
      if (e.message.includes('already exists')) console.log("isReject already exists.");
      else throw e;
    }

    // Try to add rejReason
    try {
      await pool.request().query("ALTER TABLE inv_invoiceheader ADD rejReason NVARCHAR(MAX) NULL");
      console.log("Added rejReason column.");
    } catch (e) {
      if (e.message.includes('already exists')) console.log("rejReason already exists.");
      else throw e;
    }

    console.log("Database altering completed successfully!");
    process.exit(0);
  } catch (err) {
    console.error("Error altering database:", err);
    process.exit(1);
  }
}

alterDB();
