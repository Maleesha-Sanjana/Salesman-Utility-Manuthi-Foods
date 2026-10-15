const sql = require('mssql');
const config = require('./config');

async function run() {
  try {
    const pool = await sql.connect(config);
    const result = await pool.request().query(`SELECT TOP 1 * FROM gen_salesman`);
    console.log(Object.keys(result.recordset[0]));
    process.exit(0);
  } catch (err) {
    console.error(err);
    process.exit(1);
  }
}
run();
