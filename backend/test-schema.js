const sql = require('mssql');
const config = require('./config');
async function test() {
  const pool = await sql.connect(config);
  const result = await pool.request().query("SELECT COLUMN_NAME FROM INFORMATION_SCHEMA.COLUMNS WHERE TABLE_NAME = 'gen_customer'");
  console.log(result.recordset.map(r => r.COLUMN_NAME).join(', '));
  process.exit();
}
test().catch(console.error);
