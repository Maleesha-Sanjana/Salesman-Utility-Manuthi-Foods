const sql = require('mssql');
const dbConfig = require('./config.js');

async function fix() {
  try {
    await sql.connect(dbConfig);
    console.log('Connected to DB');
    await sql.query(`
      UPDATE inv_invoiceheader 
      SET isPending = 0, isApproved = 0, isReject = 0, rejReason = NULL
      WHERE DocumentNo != '01SO00000089' -- keep the test one
    `);
    console.log('Successfully set isPending to 0 for all old rows.');
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
fix();
