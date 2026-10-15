const sql = require('mssql');
const { dbConfig } = require('./backend/config.js');

async function fix() {
  try {
    await sql.connect(dbConfig);
    console.log('Connected to DB');
    await sql.query(`
      UPDATE inv_invoiceheader 
      SET isPending = NULL, isApproved = NULL, isReject = NULL, rejReason = NULL
      WHERE DocumentNo != '01SO00000089' -- keep the test one if it exists
    `);
    console.log('Successfully set isPending to NULL for all old rows.');
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
fix();
