const sql = require('mssql');
const config = require('./config.js');

async function checkSO() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .query("SELECT * FROM inv_invoiceheader WHERE DocumentNo LIKE '%0025%'");
    console.log(result.recordset);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
checkSO();
