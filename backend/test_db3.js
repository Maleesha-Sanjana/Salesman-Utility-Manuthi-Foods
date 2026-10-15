const sql = require('mssql');
const config = require('./config.js');

(async () => {
  try {
    const pool = await sql.connect(config);
    const result = await pool.request().query(`
      SELECT SalesmanCode, SalesmanName FROM gen_salesman WHERE SalesmanCode = 'C001' OR SalesmanName LIKE '%Sahan%'
    `);
    console.log('Result:', result.recordset);
    process.exit(0);
  } catch(err) {
    console.error(err);
    process.exit(1);
  }
})();
