const sql = require('mssql');
const config = require('./config.js');

async function checkSchema() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .query(`
        SELECT COLUMN_NAME, DATA_TYPE, CHARACTER_MAXIMUM_LENGTH
        FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_NAME = 'inv_invoiceheader' AND COLUMN_NAME IN ('isPending', 'isApproved', 'isReject', 'rejReason')
      `);
    console.log(result.recordset);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
checkSchema();
