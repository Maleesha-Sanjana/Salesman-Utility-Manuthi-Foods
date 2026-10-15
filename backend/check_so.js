const sql = require('mssql');
const config = require('./config.js');

async function checkSO() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .input('docNo', sql.VarChar, '01SO00000024')
      .query('SELECT DocumentNo, isPending, isApproved, isReject, rejReason FROM inv_invoiceheader WHERE DocumentNo = @docNo');
    console.log(result.recordset);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
checkSO();
