const sql = require('mssql');
const config = require('./config.js');

async function test() {
  try {
    await sql.connect(config);
    const result = await sql.query(`
      SELECT * FROM gen_customer WHERE CustomerCode = 'C2174'
    `);
    console.log("Customer C2174 Data:", JSON.stringify(result.recordset[0], null, 2));

  } catch (e) {
    console.error(e);
  } finally {
    process.exit();
  }
}
test();
