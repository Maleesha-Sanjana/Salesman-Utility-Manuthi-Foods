const sql = require('mssql');
const config = require('./config.js');

async function checkDef() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .query(`
        SELECT COLUMN_NAME, COLUMN_DEFAULT 
        FROM INFORMATION_SCHEMA.COLUMNS 
        WHERE TABLE_NAME = 'inv_invoiceheader' AND COLUMN_NAME IN ('isPending', 'isApproved', 'isReject')
      `);
    console.log(result.recordset);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
checkDef();
