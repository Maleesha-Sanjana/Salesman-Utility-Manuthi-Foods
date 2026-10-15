const sql = require('mssql');
const dbConfig = require('./config.js');

async function fix() {
  try {
    await sql.connect(dbConfig);
    console.log('Connected to DB');
    await sql.query(`
      ALTER TABLE inv_invoiceheader ALTER COLUMN isPending BIT NULL;
      ALTER TABLE inv_invoiceheader ALTER COLUMN isApproved BIT NULL;
      ALTER TABLE inv_invoiceheader ALTER COLUMN isReject BIT NULL;
      
      UPDATE inv_invoiceheader 
      SET isPending = NULL, isApproved = NULL, isReject = NULL, rejReason = NULL
      WHERE DocumentNo != '01SO00000089' -- keep the test one
    `);
    console.log('Successfully set old rows to actual NULL.');
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
fix();
