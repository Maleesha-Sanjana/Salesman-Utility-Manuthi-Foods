const sql = require('mssql');
const config = require('./config');
async function check() {
  try {
    const pool = await sql.connect(config);
    const res = await pool.request().query("SELECT TOP 1 * FROM inv_invoiceheader");
    console.log(Object.keys(res.recordset[0] || {}));
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
check();
