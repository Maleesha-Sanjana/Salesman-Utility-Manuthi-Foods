const sql = require('mssql');
const config = require('./config.js');

async function checkSP() {
  try {
    let pool = await sql.connect(config);
    let result = await pool.request()
      .input('spName', sql.VarChar, 'inv_USp_SalesOrderPostProcess')
      .query("SELECT OBJECT_DEFINITION(OBJECT_ID(@spName)) AS SP_Definition");
    console.log(result.recordset[0].SP_Definition);
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
checkSP();
