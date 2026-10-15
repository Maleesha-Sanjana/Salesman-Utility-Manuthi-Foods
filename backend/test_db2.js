const sql = require('mssql');
const config = require('./config.js');

(async () => {
  try {
    const pool = await sql.connect(config);
    const result = await pool.request().query(`
      SELECT top 10 * FROM gen_salesman WHERE SalesmanName LIKE '%Sahan%' OR SalesmanCode IN ('C001', '0002')
    `);
    console.log(result.recordset);
    process.exit(0);
  } catch(err) {
    console.error(err);
    process.exit(1);
  }
})();
