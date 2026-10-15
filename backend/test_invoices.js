const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT TOP 5 DocumentNo, Location, CostCenter, Customer, NetAmount, BalanceAmount 
      FROM inv_invoiceheader 
      WHERE Customer = 'C2174'
      ORDER BY DocumentNo DESC
    `);
    console.log("Invoices for C2174:");
    console.table(result.recordset);
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
