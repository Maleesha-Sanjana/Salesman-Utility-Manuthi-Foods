const sql = require('mssql');
const config = require('./config.js');

(async () => {
  try {
    const pool = await sql.connect(config);
    const result = await pool.request().query(`
      SELECT COUNT(*) as count FROM gen_customer WHERE CreatedSalesman = '0002'
    `);
    console.log('Count for CreatedSalesman 0002:', result.recordset[0].count);
    process.exit(0);
  } catch(err) {
    console.error(err);
    process.exit(1);
  }
})();
