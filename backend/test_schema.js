const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT TOP 1 * FROM inv_invoiceheader 
    `);
    console.log("Schema:");
    console.log(Object.keys(result.recordset[0]));
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
