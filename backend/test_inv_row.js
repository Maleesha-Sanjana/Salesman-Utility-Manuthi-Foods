const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT * 
      FROM inv_invoiceheader 
      WHERE DocumentNo = '01IN00000828'
    `);
    console.log(result.recordset[0]);
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
