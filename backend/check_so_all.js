const sql = require('mssql');
const config = require('./config.js');

async function checkSO() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .query("SELECT TOP 5 DocumentNo, Iid, isPending, isApproved, isReject, rejReason FROM inv_invoiceheader WHERE DocumentNo LIKE '%SO%' ORDER BY DocumentNo DESC");
    console.log(result.recordset);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
checkSO();
