const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT SUM(BalanceAmount) as Outstanding 
      FROM inv_invoiceheader 
      WHERE CustomerCode = 'C2174'
    `);
    console.log("Outstanding from inv_invoiceheader:", result.recordset[0].Outstanding);

    const result2 = await sql.query(`
      SELECT LocaCode, CostCenter, SUM(BalanceAmount) as Balance 
      FROM inv_invoiceheader 
      WHERE CustomerCode = 'C2174'
      GROUP BY LocaCode, CostCenter
    `);
    console.log("Outstanding by Location/CostCenter:");
    console.table(result2.recordset);
  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
