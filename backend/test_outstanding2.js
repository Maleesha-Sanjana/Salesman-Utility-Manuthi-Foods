const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT * FROM gen_customer WHERE CustomerCode = 'C2174' OR CustomerName LIKE '%C2174%'
    `);
    console.log("gen_customer:");
    console.table(result.recordset);
    
    // Check if they have transactions anywhere
    const result2 = await sql.query(`
      SELECT TOP 5 * FROM inv_invoicemain WHERE CustomerCode = 'C2174'
    `);
    console.log("inv_invoicemain:");
    console.table(result2.recordset);
    
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
